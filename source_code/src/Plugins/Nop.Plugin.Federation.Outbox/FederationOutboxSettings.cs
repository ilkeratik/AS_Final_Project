using Nop.Core.Configuration;

namespace Nop.Plugin.Federation.Outbox;

/// <summary>
/// Stored in nopCommerce Settings table (one row per BU).
/// </summary>
public class FederationOutboxSettings : ISettings
{
    /// <summary>Short identifier for this BU, e.g. "bu-a". Written into every outbox row.</summary>
    public string StoreCode { get; set; } = string.Empty;

    /// <summary>Human-friendly store name written into outbox payload.</summary>
    public string StoreName { get; set; } = string.Empty;

    /// <summary>Whether the outbox consumer is active.</summary>
    public bool Enabled { get; set; } = true;

    /// <summary>Retain processed messages for this many days before purging (0 = keep forever).</summary>
    public int RetainProcessedDays { get; set; } = 7;

    /// <summary>
    /// Public storefront base URL for this BU, e.g. "http://localhost:5001".
    /// Used to build deep-link product URLs written into outbox payloads.
    /// </summary>
    public string StorefrontBaseUrl { get; set; } = string.Empty;
}


