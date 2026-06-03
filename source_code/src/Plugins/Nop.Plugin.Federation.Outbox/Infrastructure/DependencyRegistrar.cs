using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Nop.Core.Infrastructure;
using Nop.Plugin.Federation.Outbox.Services;

namespace Nop.Plugin.Federation.Outbox.Infrastructure;

public class NopStartup : INopStartup
{
    public void ConfigureServices(IServiceCollection services, IConfiguration configuration)
    {
        // Singleton: one cache entry shared across all three event consumers.
        // Eliminates per-event DB round-trips for settings lookups.
        services.AddSingleton<IOutboxSettingsCache, OutboxSettingsCache>();

        services.AddScoped<IOutboxService, OutboxService>();

        // Run product backfill once per app boot with full DI support.
        services.AddHostedService<OutboxSeedHostedService>();
    }

    public void Configure(IApplicationBuilder application) { }

    public int Order => 1;
}
