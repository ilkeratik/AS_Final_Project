namespace Nop.Plugin.Federation.Outbox.Services;

/// <summary>
/// Single shared point for reading and caching <see cref="FederationOutboxSettings"/>.
/// Registered as <b>Singleton</b> so the cache is shared across all three event consumers.
/// </summary>
public interface IOutboxSettingsCache
{
    /// <summary>Returns current settings, loading from DB at most once per 60 seconds.</summary>
    ValueTask<FederationOutboxSettings> GetAsync();

    /// <summary>Evicts the cached value — call after operator saves new settings.</summary>
    void Invalidate();
}

