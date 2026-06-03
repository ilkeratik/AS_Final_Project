using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Routing;
using Nop.Web.Framework.Mvc.Routing;

namespace Nop.Plugin.ExternalAuth.Keycloak.Infrastructure;

/// <summary>Registers routes for the Keycloak external auth controller.</summary>
public class RouteProvider : IRouteProvider
{
    public int Priority => -1;

    public void RegisterRoutes(IEndpointRouteBuilder endpointRouteBuilder)
    {
        endpointRouteBuilder.MapControllerRoute(
            name: "Plugin.ExternalAuth.Keycloak.Login",
            pattern: "keycloakauthentication/login",
            defaults: new { controller = "KeycloakAuthentication", action = "Login" });

        // Important: this is the app-level callback endpoint (after OIDC middleware finishes
        // processing /keycloakauthentication/callback and signs into ExternalAuthentication cookie).
        // Do not map the OIDC transport callback path itself to this action.
        endpointRouteBuilder.MapControllerRoute(
            name: "Plugin.ExternalAuth.Keycloak.LoginCallback",
            pattern: "keycloakauthentication/login-callback",
            defaults: new { controller = "KeycloakAuthentication", action = "LoginCallback" });
    }
}

