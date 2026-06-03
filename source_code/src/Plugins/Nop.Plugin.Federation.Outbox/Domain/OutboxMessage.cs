using Nop.Core;

namespace Nop.Plugin.Federation.Outbox.Domain;

/// <summary>
/// A single entry in the transactional outbox table.
/// The KafkaRelay polls rows where <see cref="ProcessedOnUtc"/> is null and publishes them to Kafka,
/// then marks them processed.
/// </summary>
public class OutboxMessage : BaseEntity
{
    /// <summary>
    /// Globally-unique, stable event identifier used for idempotency.
    /// Format: {storeCode}.{eventType}.{entityId}.{utcTicks}
    /// </summary>
    public string MessageId { get; set; } = string.Empty;

    /// <summary>BU identifier, e.g. "bu-a".</summary>
    public string StoreCode { get; set; } = string.Empty;

    /// <summary>Human-readable store name.</summary>
    public string StoreName { get; set; } = string.Empty;

    /// <summary>One of FederationOutboxDefaults.EventTypes.*</summary>
    public string EventType { get; set; } = string.Empty;

    /// <summary>Kafka topic to publish to.</summary>
    public string Topic { get; set; } = FederationOutboxDefaults.KafkaTopic;

    /// <summary>
    /// JSON-serialised event payload (ProductChangedMessage, OrderPlacedMessage, CustomerCreatedMessage…).
    /// </summary>
    public string Payload { get; set; } = string.Empty;

    /// <summary>
    /// Distributed tracing correlation ID (GUID string).
    /// Propagated as the <c>X-Correlation-Id</c> Kafka header for end-to-end observability (§6.3).
    /// </summary>
    public string? CorrelationId { get; set; }

    /// <summary>UTC time the event was captured.</summary>
    public DateTime CreatedOnUtc { get; set; }

    /// <summary>UTC time the KafkaRelay successfully published this message. Null = pending.</summary>
    public DateTime? ProcessedOnUtc { get; set; }

    /// <summary>Error text if the last relay attempt failed.</summary>
    public string? LastError { get; set; }

    /// <summary>Number of delivery attempts by the KafkaRelay.</summary>
    public int Attempts { get; set; }

    /// <summary>
    /// The entity primary key (product.Id, order.Id, customer.Id…).
    /// Used by <see cref="Services.OutboxService.HasBeenEnqueuedAsync"/> to prevent
    /// duplicate seed rows on startup without relying on MessageId string parsing.
    /// </summary>
    public int? EntityId { get; set; }

    // ── Factory ───────────────────────────────────────────────────────────────

    /// <summary>
    /// Generates a stable MessageId, a fresh CorrelationId, and a single
    /// consistent UTC timestamp — eliminating repeated boilerplate in all consumers.
    /// </summary>
    public static (string MessageId, string CorrelationId, DateTime OccurredOnUtc) NewContext(
        string storeCode, string eventType, int entityId)
    {
        var now           = DateTime.UtcNow;
        var correlationId = Guid.NewGuid().ToString("D");
        var messageId     = $"{storeCode}.{eventType}.{entityId}.{now.Ticks}";
        return (messageId, correlationId, now);
    }

    /// <summary>
    /// PostgreSQL outbox columns use <c>timestamp without time zone</c>.
    /// Npgsql rejects <see cref="DateTimeKind.Utc"/> for that type, so values written
    /// to DB must be normalized to <see cref="DateTimeKind.Unspecified"/>.
    /// Payload timestamps can remain true UTC.
    /// </summary>
    public static DateTime ToDatabaseTime(DateTime value)
        => value.Kind == DateTimeKind.Unspecified
            ? value
            : DateTime.SpecifyKind(value, DateTimeKind.Unspecified);
}


