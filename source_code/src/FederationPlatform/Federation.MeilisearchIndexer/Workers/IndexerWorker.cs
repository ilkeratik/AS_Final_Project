using Confluent.Kafka;
using Confluent.Kafka.Admin;
using Federation.Contracts;
using Meilisearch;
using Newtonsoft.Json;

namespace Federation.MeilisearchIndexer.Workers;

/// <summary>
/// Consumes <see cref="ProductChangedMessage"/> events from Kafka and maintains
/// the unified <c>products</c> Meilisearch index.
/// Document ID = "{storeCode}-{productId}" — guaranteed unique across all BUs.
///
/// Optimization: messages are drained into a batch (up to <see cref="MaxBatchSize"/>
/// within <see cref="BatchWindowMs"/> ms) before a single bulk Meilisearch call.
/// This reduces HTTP round-trips from N to 2 per batch window during catalog imports.
/// </summary>
public sealed class IndexerWorker : BackgroundService
{
    private const string IndexName    = "products";
    private const int    MaxBatchSize = 50;
    private const int    BatchWindowMs = 500;

    private readonly string _bootstrapServers;
    private readonly string _groupId;
    private readonly string _topic;
    private readonly MeilisearchClient _meili;
    private readonly ILogger<IndexerWorker> _logger;

    public IndexerWorker(
        string bootstrapServers, string groupId, string topic,
        MeilisearchClient meili, ILogger<IndexerWorker> logger)
    {
        _bootstrapServers = bootstrapServers;
        _groupId          = groupId;
        _topic            = topic;
        _meili            = meili;
        _logger           = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("[Indexer] Starting. Kafka={Kafka}", _bootstrapServers);

        await EnsureIndexAsync();

        var cfg = new ConsumerConfig
        {
            BootstrapServers = _bootstrapServers,
            GroupId          = _groupId,
            AutoOffsetReset  = AutoOffsetReset.Earliest,
            EnableAutoCommit = false
        };

        using var consumer = new ConsumerBuilder<string, string>(cfg).Build();
        using var admin = new AdminClientBuilder(new AdminClientConfig
        {
            BootstrapServers = _bootstrapServers
        }).Build();
        
        // Wait for topic to be available before subscribing (handles race condition during startup).
        await EnsureTopicAvailableAsync(admin, stoppingToken);
        
        consumer.Subscribe(_topic);

        var index = _meili.Index(IndexName);

        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                var batch = DrainBatch(consumer, stoppingToken);

                if (batch.Count == 0)
                    continue;

                try
                {
                    await ProcessBatchAsync(index, batch);
                    // Commit the watermark offset for the whole batch in one call.
                    consumer.Commit(batch[^1]);
                }
                catch (ConsumeException ex) when (ex.Error.IsFatal)
                {
                    _logger.LogCritical(ex, "[Indexer] Fatal Kafka error — stopping.");
                    break;
                }
                catch (OperationCanceledException) { break; }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "[Indexer] Batch processing error — backing off 2 s.");
                    await Task.Delay(2_000, stoppingToken);
                }
            }
        }
        finally
        {
            consumer.Close();
        }
    }

    // ── Batch drain ───────────────────────────────────────────────────────────

    /// <summary>
    /// Non-blocking drain: collects up to <see cref="MaxBatchSize"/> messages within
    /// <see cref="BatchWindowMs"/> ms, then returns whatever was accumulated.
    /// Uses short 50 ms poll timeouts so we don't block past the window deadline.
    /// Non-fatal <see cref="ConsumeException"/> (e.g. topic not yet available) returns
    /// an empty batch so the caller can retry rather than crashing the host.
    /// </summary>
    private List<ConsumeResult<string, string>> DrainBatch(
        IConsumer<string, string> consumer, CancellationToken ct)
    {
        var batch    = new List<ConsumeResult<string, string>>(MaxBatchSize);
        var deadline = Environment.TickCount64 + BatchWindowMs;

        while (batch.Count < MaxBatchSize && Environment.TickCount64 < deadline && !ct.IsCancellationRequested)
        {
            var remaining = (int)(deadline - Environment.TickCount64);
            if (remaining <= 0) break;

            try
            {
                var r = consumer.Consume(TimeSpan.FromMilliseconds(Math.Min(remaining, 50)));
                if (r is not null)
                    batch.Add(r);
            }
            catch (ConsumeException ex) when (!ex.Error.IsFatal)
            {
                // Transient errors (topic not yet available, rebalance in progress, etc.)
                // — return whatever we have so far; ExecuteAsync will retry on the next tick.
                _logger.LogWarning("[Indexer] Transient consume error ({Code}), will retry.",
                    ex.Error.Code);
                break;
            }
        }

        return batch;
    }

    // ── Batch process ─────────────────────────────────────────────────────────

    private async Task ProcessBatchAsync(
        Meilisearch.Index index,
        List<ConsumeResult<string, string>> batch)
    {
        var upserts = new List<ProductDocument>(batch.Count);
        var deletes = new List<string>();

        foreach (var r in batch)
        {
            var msg = JsonConvert.DeserializeObject<ProductChangedMessage>(r.Message.Value);
            if (msg is null)
            {
                _logger.LogWarning("[Indexer] Skipping unreadable Kafka payload at offset {Offset}.", r.Offset);
                continue;
            }

            var docId = $"{msg.StoreCode}-{msg.ProductId}";
            _logger.LogDebug("[Indexer] Kafka message {MessageId} ({EventType}) for {DocId}.",
                msg.MessageId, msg.EventType, docId);

            if (string.Equals(msg.EventType, "product.deleted",     StringComparison.OrdinalIgnoreCase) ||
                string.Equals(msg.EventType, "product.unpublished", StringComparison.OrdinalIgnoreCase))
                deletes.Add(docId);
            else
                upserts.Add(ToDocument(msg, docId));
        }

        if (upserts.Count > 0)
        {
            _logger.LogInformation("[Indexer] Upserting {Count} document(s) into Meilisearch.", upserts.Count);
            await index.AddDocumentsAsync(upserts, primaryKey: "id");
            _logger.LogInformation("[Indexer] Bulk upserted {Count} documents", upserts.Count);
        }

        if (deletes.Count > 0)
        {
            _logger.LogInformation("[Indexer] Deleting {Count} document(s) from Meilisearch: {Ids}",
                deletes.Count, string.Join(", ", deletes));
            try
            {
                var taskInfo = await index.DeleteDocumentsAsync(deletes);
                _logger.LogInformation("[Indexer] Meilisearch delete task enqueued (taskUid={TaskUid}). Waiting for completion…", taskInfo.TaskUid);

                // Wait for the async Meilisearch task to finish so we know the delete actually landed.
                var finalTask = await index.WaitForTaskAsync(taskInfo.TaskUid, 10_000, 50);
                if (finalTask.Status == TaskInfoStatus.Failed)
                {
                    _logger.LogError("[Indexer] Meilisearch delete task {TaskUid} FAILED ({Error}) — falling back to per-document deletes.",
                        taskInfo.TaskUid, finalTask.Error?.ToString());
                    await DeleteDocumentsOneByOneAsync(index, deletes);
                }
                else
                {
                    _logger.LogInformation("[Indexer] Meilisearch delete task {TaskUid} completed: {Status}. Removed {Count} document(s).",
                        taskInfo.TaskUid, finalTask.Status, deletes.Count);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[Indexer] DeleteDocumentsAsync threw — falling back to per-document deletes.");
                await DeleteDocumentsOneByOneAsync(index, deletes);
            }
        }
    }

    private async Task DeleteDocumentsOneByOneAsync(Meilisearch.Index index, List<string> docIds)
    {
        foreach (var docId in docIds)
        {
            try
            {
                var taskInfo = await index.DeleteDocumentsAsync(new[] { docId });
                var finalTask = await index.WaitForTaskAsync(taskInfo.TaskUid, 5_000, 50);
                if (finalTask.Status == TaskInfoStatus.Failed)
                    _logger.LogError("[Indexer] Per-document delete of '{DocId}' FAILED (taskUid={TaskUid}).", docId, taskInfo.TaskUid);
                else
                    _logger.LogInformation("[Indexer] Per-document delete of '{DocId}' succeeded (taskUid={TaskUid}, status={Status}).", docId, taskInfo.TaskUid, finalTask.Status);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[Indexer] Per-document delete of '{DocId}' threw an exception.", docId);
            }
        }
    }

    private static ProductDocument ToDocument(ProductChangedMessage msg, string docId) => new()
    {
        Id               = docId,
        StoreCode        = msg.StoreCode,
        StoreName        = msg.StoreName,
        ProductId        = msg.ProductId,
        ProductName      = msg.ProductName      ?? string.Empty,
        ShortDescription = msg.ShortDescription ?? string.Empty,
        Price            = msg.Price,
        ThumbnailUrl     = msg.ThumbnailUrl,
        ProductUrl       = msg.ProductUrl,
        Slug             = msg.Slug,
        Categories       = msg.Categories,
        PublishedAt      = msg.OccurredOnUtc.UtcDateTime
    };

    // ── Topic readiness ───────────────────────────────────────────────────────

    /// <summary>
    /// Ensures the Kafka topic exists by creating it via the AdminClient.
    /// Uses <see cref="CreateTopicsAsync"/> which returns cleanly when the topic
    /// already exists (<see cref="ErrorCode.TopicAlreadyExists"/>).
    /// Retries with exponential back-off up to ~2 minutes for transient broker errors.
    /// </summary>
    private async Task EnsureTopicAvailableAsync(IAdminClient admin, CancellationToken ct)
    {
        const int maxRetries = 12; // ~2 min total with exponential backoff
        int retries = 0;

        while (retries < maxRetries && !ct.IsCancellationRequested)
        {
            try
            {
                await admin.CreateTopicsAsync(new[]
                {
                    new TopicSpecification { Name = _topic, NumPartitions = 1, ReplicationFactor = 1 }
                });
                _logger.LogInformation("[Indexer] Topic '{Topic}' created.", _topic);
                return;
            }
            catch (CreateTopicsException ex)
                when (ex.Results.All(r => r.Error.Code == ErrorCode.TopicAlreadyExists))
            {
                _logger.LogInformation("[Indexer] Topic '{Topic}' already exists — ready.", _topic);
                return;
            }
            catch (Exception ex)
            {
                int delayMs = Math.Min(1000 * (1 << retries), 5_000);
                retries++;
                _logger.LogWarning(ex,
                    "[Indexer] Topic '{Topic}' not ready (retry {Retry}/{Max}) — waiting {Delay}ms",
                    _topic, retries, maxRetries, delayMs);
                await Task.Delay(delayMs, ct);
            }
        }

        _logger.LogError("[Indexer] Could not ensure topic '{Topic}' after {Retries} retries — proceeding anyway.",
            _topic, retries);
    }

    // ── Index setup ───────────────────────────────────────────────────────────

    private async Task EnsureIndexAsync()
    {
        try
        {
            await _meili.CreateIndexAsync(IndexName, "id");
            var index = _meili.Index(IndexName);

            await index.UpdateSearchableAttributesAsync(
                ["productName", "shortDescription", "categories", "storeName", "slug"]);
            await index.UpdateFilterableAttributesAsync(
                ["storeCode", "categories", "price"]);
            await index.UpdateSortableAttributesAsync(
                ["price", "publishedAt"]);
            await index.UpdateRankingRulesAsync(
                ["words", "typo", "proximity", "attribute", "sort", "exactness"]);
            await index.UpdateDisplayedAttributesAsync(
                ["id", "storeCode", "storeName", "productId", "productName",
                 "shortDescription", "price", "thumbnailUrl", "productUrl", "slug",
                 "categories", "publishedAt"]);

            _logger.LogInformation("[Indexer] Meilisearch index '{Index}' ready.", IndexName);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "[Indexer] Index setup skipped (may already be configured).");
        }
    }
}

/// <summary>Flattened document stored in Meilisearch.</summary>
public sealed class ProductDocument
{
    public string  Id               { get; set; } = string.Empty;
    public string  StoreCode        { get; set; } = string.Empty;
    public string  StoreName        { get; set; } = string.Empty;
    public int     ProductId        { get; set; }
    public string  ProductName      { get; set; } = string.Empty;
    public string  ShortDescription { get; set; } = string.Empty;
    public decimal Price            { get; set; }
    public string? ThumbnailUrl     { get; set; }
    public string? ProductUrl       { get; set; }
    public string? Slug             { get; set; }
    public List<string> Categories  { get; set; } = [];
    public DateTime     PublishedAt { get; set; }
}