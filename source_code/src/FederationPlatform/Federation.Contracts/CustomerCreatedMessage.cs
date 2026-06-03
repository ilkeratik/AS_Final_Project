namespace Federation.Contracts;

/// <summary>
/// Published Language (PL) for the <c>customers.created</c> Kafka topic.
/// Produced by each BU Commerce Context when a customer registers.
/// Consumed by the Group CRM (EspoCRM) and the Identity Provider (Keycloak) to
/// establish SSO credentials — see §6.3 IAM and shared identity flow.
/// </summary>
public sealed record CustomerCreatedMessage
{
    /// <summary>Globally-unique message ID. Format: {storeCode}.customer.created.{customerId}.{utcTicks}</summary>
    public required string MessageId { get; init; }

    /// <summary>Distributed tracing correlation ID (§6.3 Observability).</summary>
    public string? CorrelationId { get; init; }

    /// <summary>bu-a | bu-b</summary>
    public required string StoreCode { get; init; }

    /// <summary>Human-readable store name.</summary>
    public required string StoreName { get; init; }

    /// <summary>customer.created | customer.updated</summary>
    public required string EventType { get; init; }

    public required int CustomerId { get; init; }
    public required Guid CustomerGuid { get; init; }

    /// <summary>Email address — null for guests (guests are filtered out before publishing).</summary>
    public string? Email { get; init; }

    public string? Username { get; init; }

    public DateTimeOffset OccurredOnUtc { get; init; }
}

