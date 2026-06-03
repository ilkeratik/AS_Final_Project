using LinqToDB;
using Nop.Data;
using Nop.Plugin.Federation.Outbox.Domain;
using Nop.Services.Logging;

namespace Nop.Plugin.Federation.Outbox.Services;

public class OutboxService : IOutboxService
{
    private readonly IRepository<OutboxMessage> _repo;
    private readonly ILogger _logger;

    public OutboxService(IRepository<OutboxMessage> repo, ILogger logger)
    {
        _repo = repo;
        _logger = logger;
    }

    /// <summary>
    /// Idempotent insert: skips silently if a row with the same MessageId already exists.
    /// One SELECT EXISTS + one INSERT = 2 round-trips (minimum safe for idempotency).
    /// </summary>
    public async Task EnqueueAsync(OutboxMessage message)
    {
        var exists = await _repo.Table.AnyAsync(m => m.MessageId == message.MessageId);
        if (exists)
        {
            await _logger.InformationAsync(
                $"[Federation.Outbox] Skipped duplicate message {message.MessageId} for {message.StoreCode} entity {message.EntityId} ({message.EventType}).");
            return;
        }

        message.CreatedOnUtc = message.CreatedOnUtc == default
            ? OutboxMessage.ToDatabaseTime(DateTime.UtcNow)
            : OutboxMessage.ToDatabaseTime(message.CreatedOnUtc);
        await _repo.InsertAsync(message);

        await _logger.InformationAsync(
            $"[Federation.Outbox] Enqueued message {message.MessageId} for {message.StoreCode} entity {message.EntityId} ({message.EventType}) to topic '{message.Topic}'.");
    }

    /// <inheritdoc/>
    public async Task<bool> HasAnyAsync()
        => await _repo.Table.AnyAsync(m => m.Id > 0);

    /// <inheritdoc/>
    public async Task<bool> HasBeenEnqueuedAsync(string storeCode, int entityId)
        => await _repo.Table.AnyAsync(m => m.StoreCode == storeCode && m.EntityId == entityId);

    /// <inheritdoc/>
    public async Task<bool> HasEventEnqueuedAsync(string storeCode, int entityId, string eventType)
        => await _repo.Table.AnyAsync(m =>
            m.StoreCode == storeCode &&
            m.EntityId == entityId &&
            m.EventType == eventType);

    public async Task<IList<OutboxMessage>> GetPendingAsync(int batchSize = 100)
        => await _repo.Table
            .Where(m => m.ProcessedOnUtc == null && m.Attempts < FederationOutboxDefaults.MaxAttempts)
            .OrderBy(m => m.CreatedOnUtc)
            .Take(batchSize)
            .ToListAsync();

    /// <summary>
    /// Set-based UPDATE — one SQL statement, no GET round-trip.
    /// </summary>
    public async Task MarkProcessedAsync(int id)
        => await _repo.Table
            .Where(m => m.Id == id)
            .Set(m => m.ProcessedOnUtc, OutboxMessage.ToDatabaseTime(DateTime.UtcNow))
            .UpdateAsync();

    /// <summary>
    /// Set-based UPDATE — one SQL statement, no GET round-trip.
    /// </summary>
    public async Task RecordFailureAsync(int id, string error)
        => await _repo.Table
            .Where(m => m.Id == id)
            .Set(m => m.Attempts,  m => m.Attempts + 1)
            .Set(m => m.LastError, error.Length > 2000 ? error[..2000] : error)
            .UpdateAsync();

    /// <summary>
    /// Set-based DELETE — single SQL statement, no memory allocation for the result set.
    /// Replaces the previous load-all-then-delete pattern which was O(N) in memory.
    /// </summary>
    public async Task PurgeProcessedAsync(int retainDays)
    {
        if (retainDays <= 0) return;
        var cutoff = OutboxMessage.ToDatabaseTime(DateTime.UtcNow.AddDays(-retainDays));
        await _repo.Table
            .Where(m => m.ProcessedOnUtc != null && m.ProcessedOnUtc < cutoff)
            .DeleteAsync();
    }
}
