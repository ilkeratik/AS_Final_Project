namespace Nop.Plugin.Federation.Outbox;

public static class FederationOutboxDefaults
{
    public const string SystemName = "Misc.Federation.Outbox";

    /// <summary>
    /// Maximum relay delivery attempts before a message is abandoned.
    /// Must match the value used in the KafkaRelay worker.
    /// </summary>
    public const int MaxAttempts = 5;

    // ── Kafka topics ──────────────────────────────────────────────────────────
    /// <summary>Product catalog events (ADR-3 / §8.6 Shared Discovery Flow).</summary>
    public const string KafkaTopic = "federation.products";

    /// <summary>Order lifecycle events (§6.2 / QA-1 / diagram 8.5).</summary>
    public const string OrdersTopic = "orders.placed";

    /// <summary>Customer registration events (§6.3 IAM + CRM sync).</summary>
    public const string CustomersTopic = "customers.created";

    public static class EventTypes
    {
        // ── product events ──────────────────────────────────────────────────
        public const string Published   = "product.published";
        public const string Updated     = "product.updated";
        public const string Unpublished = "product.unpublished";
        public const string Deleted     = "product.deleted";

        // ── order events ────────────────────────────────────────────────────
        public const string OrderPlaced    = "order.placed";
        public const string OrderUpdated   = "order.updated";
        public const string OrderCancelled = "order.cancelled";

        // ── customer events ─────────────────────────────────────────────────
        public const string CustomerCreated = "customer.created";
        public const string CustomerUpdated = "customer.updated";
    }
}
