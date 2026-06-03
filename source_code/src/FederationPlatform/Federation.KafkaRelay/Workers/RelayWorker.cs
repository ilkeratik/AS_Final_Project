using Confluent.Kafka;
using Dapper;
using Npgsql;
using System.Text;
using System.Text.Json;

namespace Federation.KafkaRelay.Workers;

/// <summary>
/// Polls the <c>OutboxMessage</c> table in one BU's PostgreSQL database,
/// publishes unprocessed rows to Kafka with distributed tracing headers,
/// then marks them processed.
/// Implements ADR-2 reliability loop (at-least-once delivery, idempotent restart).
///
/// Meilisearch watchdog: on startup (after 30 s) and every 5 minutes, checks whether
/// the <c>products</c> index has 0 documents. If so, and there are previously-processed
/// outbox rows, it resets <c>ProcessedOnUtc</c> so the relay re-publishes them to Kafka
/// and the indexer rebuilds the index automatically — no manual intervention required.
/// </summary>
public sealed class RelayWorker : BackgroundService
{
    private const int BatchSize      = 50;
    private const int PollIntervalMs = 5_000;
    private const int MaxBackoffMs   = 60_000;

    /// <summary>
    /// Must match <c>FederationOutboxDefaults.MaxAttempts</c> in the nopCommerce plugin.
    /// </summary>
    private const int MaxAttempts = 5;

    private const int WatchdogInitialDelayMs = 30_000;   // 30 s — let Meili boot
    private const int WatchdogIntervalMs     = 300_000;  // 5 min

    private readonly string _connectionString;
    private readonly string _storeCode;
    private readonly string _bootstrapServers;
    private readonly string _meilisearchUrl;
    private readonly HttpClient _http;
    private readonly ILogger<RelayWorker> _logger;

    private int _consecutiveErrors;

    public RelayWorker(
        string connectionString,
        string storeCode,
        string bootstrapServers,
        string meilisearchUrl,
        ILogger<RelayWorker> logger)
    {
        _connectionString = connectionString;
        _storeCode        = storeCode;
        _bootstrapServers = bootstrapServers;
        _meilisearchUrl   = meilisearchUrl.TrimEnd('/');
        _http             = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
        _logger           = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("[Relay:{StoreCode}] Starting. Kafka={Kafka} Meili={Meili}",
            _storeCode, _bootstrapServers, _meilisearchUrl);

        var producerCfg = new ProducerConfig
        {
            BootstrapServers      = _bootstrapServers,
            Acks                  = Acks.All,
            EnableIdempotence     = true,
            MessageSendMaxRetries = 5
        };

        using var producer = new ProducerBuilder<string, string>(producerCfg).Build();

        // Watchdog fires after initial delay, then every 5 minutes.
        var nextWatchdog = DateTimeOffset.UtcNow.AddMilliseconds(WatchdogInitialDelayMs);

        while (!stoppingToken.IsCancellationRequested)
        {
            // ── Meilisearch watchdog ──────────────────────────────────────────
            if (DateTimeOffset.UtcNow >= nextWatchdog)
            {
                try
                {
                    await CheckAndRestoreIndexAsync(stoppingToken);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "[Relay:{StoreCode}] Watchdog error (non-fatal).", _storeCode);
                }
                nextWatchdog = DateTimeOffset.UtcNow.AddMilliseconds(WatchdogIntervalMs);
            }

            // ── Normal relay batch ────────────────────────────────────────────
            try
            {
                await RelayBatchAsync(producer, stoppingToken);
                _consecutiveErrors = 0;
            }
            catch (OperationCanceledException) { break; }
            catch (Exception ex)
            {
                _consecutiveErrors++;
                _logger.LogError(ex, "[Relay:{StoreCode}] Error (attempt {N})", _storeCode, _consecutiveErrors);
            }

            var backoff = Math.Min(PollIntervalMs * (1 << Math.Min(_consecutiveErrors, 10)), MaxBackoffMs);
            var jitter  = Random.Shared.Next(0, 1_000);
            await Task.Delay(backoff + jitter, stoppingToken);
        }

        producer.Flush(TimeSpan.FromSeconds(10));
        _logger.LogInformation("[Relay:{StoreCode}] Stopped.", _storeCode);
    }

    // ── Meilisearch watchdog ───────────────────────────────────────────────────

    /// <summary>
    /// Checks whether the Meilisearch <c>products</c> index is empty.
    /// If it is, and this BU's outbox already has previously-processed product rows,
    /// resets those rows so the relay re-publishes them and the indexer rebuilds the index.
    /// </summary>
    private async Task CheckAndRestoreIndexAsync(CancellationToken ct)
    {
        // 1. Check Meilisearch index doc count
        int docCount;
        try
        {
            var resp = await _http.GetAsync($"{_meilisearchUrl}/indexes/products/stats", ct);
            if (!resp.IsSuccessStatusCode)
            {
                _logger.LogDebug("[Relay:{StoreCode}] Watchdog: Meili stats returned {Status} — skipping.",
                    _storeCode, resp.StatusCode);
                return;
            }

            using var doc  = JsonDocument.Parse(await resp.Content.ReadAsStringAsync(ct));
            docCount = doc.RootElement.GetProperty("numberOfDocuments").GetInt32();
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "[Relay:{StoreCode}] Watchdog: could not reach Meilisearch — skipping.", _storeCode);
            return;
        }

        if (docCount > 0)
            return; // index is populated — nothing to do

        // 2. Check if this BU has any previously-processed product rows that need replaying
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.OpenAsync(ct);

        var processedCount = await conn.ExecuteScalarAsync<int>(
            """
            SELECT COUNT(*) FROM "OutboxMessage"
            WHERE  "ProcessedOnUtc" IS NOT NULL
              AND  "Topic" = 'federation.products'
            """);

        if (processedCount == 0)
        {
            // Fresh deployment — no prior data. Nothing to restore.
            _logger.LogDebug("[Relay:{StoreCode}] Watchdog: Meili empty but no processed rows — fresh deployment.", _storeCode);
            return;
        }

        // 3. Reset ProcessedOnUtc so the relay re-publishes them to Kafka
        _logger.LogWarning(
            "[Relay:{StoreCode}] Meilisearch index is empty but {Count} processed product rows found. " +
            "Resetting outbox rows for re-publication…",
            _storeCode, processedCount);

        var reset = await conn.ExecuteAsync(
            """
            UPDATE "OutboxMessage"
            SET    "ProcessedOnUtc" = NULL,
                   "Attempts"       = 0,
                   "LastError"      = NULL
            WHERE  "ProcessedOnUtc" IS NOT NULL
              AND  "Topic" = 'federation.products'
            """);

        _logger.LogInformation(
            "[Relay:{StoreCode}] Watchdog reset {Reset} product rows. Relay will re-publish within 5 s.",
            _storeCode, reset);
    }

    // ── Relay batch ───────────────────────────────────────────────────────────

    private async Task RelayBatchAsync(IProducer<string, string> producer, CancellationToken ct)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.OpenAsync(ct);
        await using var tx = await conn.BeginTransactionAsync(ct);

        var rows = (await conn.QueryAsync<OutboxRow>(
            """
            SELECT "Id", "MessageId", "Topic", "EventType", "EntityId", "Payload", "CorrelationId", "Attempts"
            FROM   "OutboxMessage"
            WHERE  "ProcessedOnUtc" IS NULL
              AND  "Attempts" < @MaxAttempts
            ORDER  BY "CreatedOnUtc"
            LIMIT  @BatchSize
            FOR UPDATE SKIP LOCKED
            """,
            new { MaxAttempts, BatchSize },
            transaction: tx
        )).AsList();

        if (rows.Count == 0)
        {
            await tx.RollbackAsync(ct);
            return;
        }

        _logger.LogInformation("[Relay:{StoreCode}] Processing {Count} outbox message(s) for Kafka.", _storeCode, rows.Count);

        var publishedCount = 0;
        var failedCount    = 0;

        foreach (var row in rows)
        {
            ct.ThrowIfCancellationRequested();

            try
            {
                _logger.LogDebug("[Relay:{StoreCode}] Publishing outbox row {Id} ({EventType}) for entity {EntityId} to topic {Topic}.",
                    _storeCode, row.Id, row.EventType, row.EntityId, row.Topic);

                var headers = new Headers
                {
                    { "X-Store-Code", Encoding.UTF8.GetBytes(_storeCode) },
                    { "X-Message-Id", Encoding.UTF8.GetBytes(row.MessageId) }
                };

                if (!string.IsNullOrEmpty(row.CorrelationId))
                    headers.Add("X-Correlation-Id", Encoding.UTF8.GetBytes(row.CorrelationId));

                var kafkaMsg = new Message<string, string>
                {
                    Key     = $"{_storeCode}.{row.MessageId}",
                    Value   = row.Payload,
                    Headers = headers
                };

                var deliveryResult = await producer.ProduceAsync(row.Topic, kafkaMsg, ct);

                switch (deliveryResult.Status)
                {
                    case PersistenceStatus.Persisted:
                        await conn.ExecuteAsync(
                            """
                            UPDATE "OutboxMessage"
                            SET    "ProcessedOnUtc" = NOW() AT TIME ZONE 'UTC'
                            WHERE  "Id" = @Id
                            """, new { row.Id }, transaction: tx);
                        publishedCount++;
                        _logger.LogDebug("[Relay:{StoreCode}] Kafka persisted row {Id} ({EventType}) for entity {EntityId}.",
                            _storeCode, row.Id, row.EventType, row.EntityId);
                        break;

                    default:
                        failedCount++;
                        _logger.LogWarning(
                            "[Relay:{StoreCode}] Kafka delivery status {Status} for row {Id} ({EventType}) entity {EntityId}; incrementing attempts.",
                            _storeCode, deliveryResult.Status, row.Id, row.EventType, row.EntityId);
                        await conn.ExecuteAsync(
                            """
                            UPDATE "OutboxMessage"
                            SET    "Attempts"  = "Attempts" + 1,
                                   "LastError" = @Error
                            WHERE  "Id" = @Id
                            """,
                            new { row.Id, Error = $"Kafka status: {deliveryResult.Status}" },
                            transaction: tx);
                        break;
                }
            }
            catch (Exception ex)
            {
                failedCount++;
                _logger.LogWarning(ex, "[Relay:{StoreCode}] Failed to deliver row {Id} ({EventType}) for entity {EntityId}.",
                    _storeCode, row.Id, row.EventType, row.EntityId);

                await conn.ExecuteAsync(
                    """
                    UPDATE "OutboxMessage"
                    SET    "Attempts"  = "Attempts" + 1,
                           "LastError" = @Error
                    WHERE  "Id" = @Id
                    """,
                    new { row.Id, Error = ex.Message[..Math.Min(ex.Message.Length, 2000)] },
                    transaction: tx);
            }
        }

        await tx.CommitAsync(ct);

        _logger.LogInformation(
            "[Relay:{StoreCode}] Kafka relay batch committed. Published {PublishedCount}, failed {FailedCount}.",
            _storeCode, publishedCount, failedCount);
    }

    private sealed record OutboxRow(int Id, string MessageId, string Topic, string EventType, int EntityId, string Payload, string? CorrelationId, int Attempts);
}
