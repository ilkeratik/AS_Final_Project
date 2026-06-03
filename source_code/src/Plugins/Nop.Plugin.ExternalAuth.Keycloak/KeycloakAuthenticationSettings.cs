using Nop.Core.Configuration;

namespace Nop.Plugin.ExternalAuth.Keycloak;

public class KeycloakAuthenticationSettings : ISettings
{
    /// <summary>Public authority URL (browser-facing), e.g. http://localhost:8080/realms/nop-federation</summary>
    public string? Authority { get; set; }

    /// <summary>
    /// Internal metadata URL for Docker environments where the browser URL differs from the
    /// container-to-container URL, e.g. http://keycloak:8080/realms/nop-federation/.well-known/openid-configuration
    /// Leave empty to derive from Authority.
    /// </summary>
    public string? MetadataAddress { get; set; }

    /// <summary>
    /// Override the expected token issuer when MetadataAddress uses a different host from Authority.
    /// Matches the issuer emitted by Keycloak (based on KC_HOSTNAME_URL).
    /// Leave empty to derive from Authority.
    /// </summary>
    public string? ValidIssuer { get; set; }

    public string? ClientId { get; set; }
    public string? ClientSecret { get; set; }
}