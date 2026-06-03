using Microsoft.AspNetCore.Mvc;
using Nop.Web.Framework.Components;

namespace Nop.Plugin.ExternalAuth.Keycloak.Components;

/// <summary>Renders the "Login with Keycloak" button on the login page.</summary>
public class KeycloakViewComponent : NopViewComponent
{
    public IViewComponentResult Invoke(string widgetZone, object additionalData)
    {
        return View("~/Plugins/ExternalAuth.Keycloak/Views/PublicInfo.cshtml");
    }
}