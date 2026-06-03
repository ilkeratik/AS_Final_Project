namespace Nop.Plugin.ExternalAuth.Keycloak;

public static class KeycloakAuthenticationDefaults
{
    public const string ProviderSystemName    = "ExternalAuth.Keycloak";
    public const string AuthenticationScheme  = "Keycloak";
    public const string LocalAuthority        = "http://localhost:8080/realms/nop-federation";
    public const string LocalMetadataAddress  = "http://keycloak:8080/realms/nop-federation/.well-known/openid-configuration";

    /// <summary>OIDC callback path — must match redirectUris in the Keycloak realm client config.</summary>
    public const string CallbackPath          = "/keycloakauthentication/callback";

    public static string BuildMetadataAddress(string authority)
        => $"{authority.TrimEnd('/')}/.well-known/openid-configuration";
}