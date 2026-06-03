using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using Nop.Core.Infrastructure;
using Nop.Services.Authentication.External;

namespace Nop.Plugin.ExternalAuth.Keycloak.Infrastructure;

/// <summary>
/// Registers the Keycloak OIDC authentication scheme with ASP.NET Core.
/// Priority: DB settings (ISettingService) → environment variables (IConfiguration) → local-dev defaults.
/// This allows Docker deployments to use Keycloak__* env vars without requiring DB seeding.
/// </summary>
public class KeycloakAuthenticationRegistrar : IExternalAuthenticationRegistrar
{
    public void Configure(AuthenticationBuilder builder)
    {
        builder.AddOpenIdConnect(KeycloakAuthenticationDefaults.AuthenticationScheme, options =>
        {
            // 1. DB settings (populated via Admin Panel or InstallAsync)
            var settings = EngineContext.Current.Resolve<KeycloakAuthenticationSettings>();
            // 2. Environment / appsettings fallback (Keycloak:Authority, Keycloak:ClientId, …)
            var config   = EngineContext.Current.Resolve<IConfiguration>();

            var authority    = Coalesce(settings?.Authority,    config["Keycloak:Authority"],    KeycloakAuthenticationDefaults.LocalAuthority)!;
            var clientId     = Coalesce(settings?.ClientId,     config["Keycloak:ClientId"]);
            var clientSecret = Coalesce(settings?.ClientSecret, config["Keycloak:ClientSecret"]);
            var metaAddr     = Coalesce(settings?.MetadataAddress, config["Keycloak:MetadataAddress"]);
            var validIssuer  = Coalesce(settings?.ValidIssuer,  config["Keycloak:ValidIssuer"], authority);

            // Skip OIDC registration if client credentials are not yet configured.
            // This prevents startup errors on fresh installs before the admin has set ClientId.
            if (string.IsNullOrEmpty(clientId))
                return;

            options.Authority    = authority;
            options.ClientId     = clientId;
            options.ClientSecret = clientSecret;

            options.ResponseType                  = OpenIdConnectResponseType.Code;
            options.ResponseMode                  = OpenIdConnectResponseMode.Query;
            options.SaveTokens                    = true;
            options.RequireHttpsMetadata          = false;
            options.GetClaimsFromUserInfoEndpoint = true;
            options.CallbackPath                  = KeycloakAuthenticationDefaults.CallbackPath;

            // Local development runs over plain HTTP on localhost, so the default
            // remote-auth cookie settings can prevent nonce/correlation cookies
            // from round-tripping back on the callback request.
            options.CorrelationCookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
            options.CorrelationCookie.SameSite     = SameSiteMode.Lax;
            options.NonceCookie.SecurePolicy       = CookieSecurePolicy.SameAsRequest;
            options.NonceCookie.SameSite           = SameSiteMode.Lax;

            // Internal Docker metadata URL — separates server-side OIDC discovery from the public authority URL.
            options.MetadataAddress = !string.IsNullOrEmpty(metaAddr)
                ? metaAddr
                : string.Equals(authority, KeycloakAuthenticationDefaults.LocalAuthority, StringComparison.OrdinalIgnoreCase)
                    ? KeycloakAuthenticationDefaults.LocalMetadataAddress
                    : KeycloakAuthenticationDefaults.BuildMetadataAddress(authority);

            // Issuer override for KC_HOSTNAME_URL deployments.
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidIssuer    = validIssuer,
                ValidateIssuer = true,
                NameClaimType  = "preferred_username",
                RoleClaimType  = "roles"
            };

            options.Events = new OpenIdConnectEvents
            {
                OnRemoteFailure = ctx =>
                {
                    ctx.HandleResponse();
                    ctx.Response.Redirect($"/login?returnUrl={Uri.EscapeDataString(ctx.Properties?.RedirectUri ?? "/")}");
                    return Task.CompletedTask;
                }
            };
        });
    }

    /// <summary>Returns the first non-null, non-empty value from the candidates.</summary>
    private static string? Coalesce(params string?[] candidates)
    {
        foreach (var c in candidates)
            if (!string.IsNullOrEmpty(c)) return c;
        return null;
    }
}



