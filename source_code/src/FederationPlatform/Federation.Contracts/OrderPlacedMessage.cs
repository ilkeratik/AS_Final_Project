namespace Federation.Contracts;

/// <summary>
/// Published Language (PL) for the <c>orders.placed</c> Kafka topic.
/// Produced by each BU Commerce Context (Open-Host Service).
/// Consumed by BU Fulfillment ERPs and the Group CRM.
/// See ADR-2 and QA-Scenario 1 (Fault Containment).
/// </summary>
public sealed record OrderPlacedMessage
{
    /// <summary>Globally-unique message ID. Format: {storeCode}.order.placed.{orderId}.{utcTicks}</summary>
    public required string MessageId { get; init; }

    /// <summary>Distributed tracing correlation ID (§6.3 Observability).</summary>
    public string? CorrelationId { get; init; }

    /// <summary>bu-a | bu-b</summary>
    public required string StoreCode { get; init; }

    /// <summary>Human-readable store name.</summary>
    public required string StoreName { get; init; }

    /// <summary>order.placed | order.updated | order.cancelled</summary>
    public required string EventType { get; init; }

    public required int OrderId { get; init; }
    public required Guid OrderGuid { get; init; }
    public required int CustomerId { get; init; }

    public decimal OrderTotal { get; init; }
    public string? CurrencyCode { get; init; }
    public string? PaymentMethodSystemName { get; init; }

    /// <summary>nopCommerce OrderStatus enum value (Pending=10, Processing=20, Complete=30, Cancelled=40).</summary>
    public int OrderStatus { get; init; }

    public DateTimeOffset OccurredOnUtc { get; init; }
}

