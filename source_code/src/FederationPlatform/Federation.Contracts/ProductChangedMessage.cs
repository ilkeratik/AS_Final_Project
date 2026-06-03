namespace Federation.Contracts;

/// <summary>
/// Canonical event published to the Kafka topic "federation.products".
/// Produced by Federation.KafkaRelay (read from BU outbox tables).
/// Consumed by Federation.MeilisearchIndexer.
/// </summary>
public sealed record ProductChangedMessage
{
    /// <summary>Globally-unique, stable ID. Format: {storeCode}.product.{eventType}.{productId}.{utcTicks}</summary>
    public required string MessageId { get; init; }

    /// <summary>bu-a | bu-b (expandable)</summary>
    public required string StoreCode { get; init; }

    /// <summary>Human-readable store name, e.g. "HomeStyle Living"</summary>
    public required string StoreName { get; init; }

    /// <summary>product.published | product.updated | product.deleted | product.unpublished</summary>
    public required string EventType { get; init; }

    public required int ProductId { get; init; }

    public string? ProductName { get; init; }
    public string? ShortDescription { get; init; }
    public decimal Price { get; init; }
    public string? ThumbnailUrl { get; init; }
    public string? ProductUrl { get; init; }
    public string? Slug { get; init; }
    public List<string> Categories { get; init; } = [];

    public DateTimeOffset OccurredOnUtc { get; init; }
}

