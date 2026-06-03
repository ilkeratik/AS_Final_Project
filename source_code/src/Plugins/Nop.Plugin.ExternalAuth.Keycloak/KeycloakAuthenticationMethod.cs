using Nop.Core;
using Nop.Plugin.ExternalAuth.Keycloak.Components;
using Nop.Services.Authentication.External;
using Nop.Services.Configuration;
using Nop.Services.Plugins;

namespace Nop.Plugin.ExternalAuth.Keycloak;

public class KeycloakAuthenticationMethod : BasePlugin, IExternalAuthenticationMethod
{
    private readonly ISettingService _settingService;
    private readonly IWebHelper _webHelper;

    public KeycloakAuthenticationMethod(ISettingService settingService, IWebHelper webHelper)
    {
        _settingService = settingService;
        _webHelper = webHelper;
    }

    /// <inheritdoc />
    public Type GetPublicViewComponent() => typeof(KeycloakViewComponent);

    public override async Task InstallAsync()
    {
        await _settingService.SaveSettingAsync(new KeycloakAuthenticationSettings
        {
            Authority       = KeycloakAuthenticationDefaults.LocalAuthority,
            ClientId        = string.Empty,   // Will be set via admin panel or federation bootstrap script
            ClientSecret    = string.Empty,   // Will be set via admin panel or federation bootstrap script
            MetadataAddress = KeycloakAuthenticationDefaults.LocalMetadataAddress,
            ValidIssuer     = KeycloakAuthenticationDefaults.LocalAuthority
        });

        await base.InstallAsync();
    }

    public override async Task UninstallAsync()
    {
        await _settingService.DeleteSettingAsync<KeycloakAuthenticationSettings>();
        await base.UninstallAsync();
    }
}