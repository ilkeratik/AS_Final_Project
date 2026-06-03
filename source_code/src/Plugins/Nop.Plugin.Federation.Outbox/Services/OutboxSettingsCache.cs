using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;
using Nop.Services.Configuration;

namespace Nop.Plugin.Federation.Outbox.Services;

/// <summary>
/// Singleton settings cache — eliminates the per-event DB round-trip that all three
/// consumers previously duplicated individually.
/// Uses a 60-second absolute expiry so operator config changes propagate within a minute.
///
/// IMPORTANT: ISettingService is Scoped (InstancePerLifetimeScope in Autofac). Injecting
/// it directly into a Singleton would create a captive dependency, holding a root-scope
/// DbContext forever. We use IServiceScopeFactory to create a short-lived scope only
/// when the cache entry needs refreshing (once per 60 seconds max).
/// </summary>
public sealed class OutboxSettingsCache : IOutboxSettingsCache
{
    private const string CacheKey = $"{FederationOutboxDefaults.SystemName}.settings.v1";

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly IMemoryCache _cache;

    public OutboxSettingsCache(IServiceScopeFactory scopeFactory, IMemoryCache cache)
    {
        _scopeFactory = scopeFactory;
        _cache        = cache;
    }

    public async ValueTask<FederationOutboxSettings> GetAsync()
    {
        // GetOrCreateAsync is race-safe: only one factory call per key even under concurrency.
        return await _cache.GetOrCreateAsync(CacheKey, async entry =>
        {
            entry.SetAbsoluteExpiration(TimeSpan.FromSeconds(60));
            // Create a short-lived scope so we get a properly-scoped ISettingService
            // (and its underlying DbContext) rather than capturing a root-scope instance.
            await using var scope    = _scopeFactory.CreateAsyncScope();
            var settingService       = scope.ServiceProvider.GetRequiredService<ISettingService>();
            return await settingService.LoadSettingAsync<FederationOutboxSettings>();
        }) ?? new FederationOutboxSettings();
    }

    public void Invalidate() => _cache.Remove(CacheKey);
}

