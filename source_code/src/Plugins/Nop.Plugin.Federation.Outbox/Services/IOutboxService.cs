using Nop.Plugin.Federation.Outbox.Domain;

namespace Nop.Plugin.Federation.Outbox.Services;

/// <summary>
/// Writes domain events to the transactional outbox table.
/// </summary>
public interface IOutboxService
{
    /// <summary>Enqueue a new outbox message. Silently no-ops if the same MessageId already exists.</summary>
    Task EnqueueAsync(OutboxMessage message);

    /// <summary>Returns true if the outbox already contains at least one row.</summary>
    Task<bool> HasAnyAsync();

    /// <summary>
    /// Returns true if this store already has at least one outbox row for the given entity.
    /// Used by the startup seed task to skip products that were already queued (organic or seeded).
    /// </summary>
    Task<bool> HasBeenEnqueuedAsync(string storeCode, int entityId);

    /// <summary>
    /// Returns true if this store already has at least one outbox row for the given entity and event type.
    /// </summary>
    Task<bool> HasEventEnqueuedAsync(string storeCode, int entityId, string eventType);

    /// <summary>Returns up to <paramref name="batchSize"/> unprocessed messages ordered by CreatedOnUtc.</summary>
    Task<IList<OutboxMessage>> GetPendingAsync(int batchSize = 100);

    /// <summary>Mark a message as successfully relayed.</summary>
    Task MarkProcessedAsync(int id);

    /// <summary>Record a relay failure and increment the attempt counter.</summary>
    Task RecordFailureAsync(int id, string error);

    /// <summary>Delete processed messages older than <paramref name="retainDays"/> days.</summary>
    Task PurgeProcessedAsync(int retainDays);
}

