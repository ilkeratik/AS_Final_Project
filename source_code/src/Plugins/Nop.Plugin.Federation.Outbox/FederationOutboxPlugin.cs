using Nop.Services.Configuration;
using Nop.Services.Plugins;

namespace Nop.Plugin.Federation.Outbox;

public class FederationOutboxPlugin : BasePlugin
{
    private readonly ISettingService _settingService;

    public FederationOutboxPlugin(ISettingService settingService)
    {
        _settingService = settingService;
    }

    public override async Task InstallAsync()
    {
        // Save safe defaults; BU bootstrap scripts overwrite these with per-store values
        // before the hosted backfill runs on installed environments.
        await _settingService.SaveSettingAsync(new FederationOutboxSettings
        {
            StoreCode         = string.Empty,   // e.g. "bu-a" — set after install
            StoreName         = string.Empty,   // e.g. "HomeStyle Living"
            Enabled           = false,          // disabled until configured
            RetainProcessedDays = 7
        });

        await base.InstallAsync();
    }

    public override async Task UninstallAsync()
    {
        await _settingService.DeleteSettingAsync<FederationOutboxSettings>();
        await base.UninstallAsync();
    }
}

