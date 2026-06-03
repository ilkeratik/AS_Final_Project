using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Mvc;
using Nop.Core;
using Nop.Services.Authentication.External;
using Nop.Services.Customers;
using Nop.Web.Framework.Controllers;

namespace Nop.Plugin.ExternalAuth.Keycloak.Controllers;

/// <summary>
/// Handles the Keycloak OIDC challenge (Login) and the post-authentication callback (LoginCallback).
/// Follows the nopCommerce external-auth pattern used by the Facebook plugin.
/// </summary>
[AutoValidateAntiforgeryToken]
public class KeycloakAuthenticationController : BasePluginController
{
    private readonly IAuthenticationPluginManager  _authenticationPluginManager;
    private readonly ICustomerService              _customerService;
    private readonly IExternalAuthenticationService _externalAuthenticationService;
    private readonly IStoreContext                 _storeContext;
    private readonly IWorkContext                  _workContext;

    public KeycloakAuthenticationController(
        IAuthenticationPluginManager  authenticationPluginManager,
        ICustomerService              customerService,
        IExternalAuthenticationService externalAuthenticationService,
        IStoreContext                 storeContext,
        IWorkContext                  workContext)
    {
        _authenticationPluginManager  = authenticationPluginManager;
        _customerService              = customerService;
        _externalAuthenticationService = externalAuthenticationService;
        _storeContext                 = storeContext;
        _workContext                  = workContext;
    }

    /// <summary>Initiates the Keycloak OIDC challenge, redirecting the browser to Keycloak.</summary>
    public async Task<IActionResult> Login(string returnUrl)
    {
        var store    = await _storeContext.GetCurrentStoreAsync();
        var customer = await _workContext.GetCurrentCustomerAsync();

        if (!await _authenticationPluginManager.IsPluginActiveAsync(
                KeycloakAuthenticationDefaults.ProviderSystemName, customer, store.Id))
            throw new NopException("Keycloak authentication plugin is not active.");

        // RedirectUri must be different from options.CallbackPath; otherwise OIDC middleware
        // receives a second callback request without state and rejects it.
        var callbackUrl = Url.Action("LoginCallback", "KeycloakAuthentication", new { returnUrl });

        var props = new AuthenticationProperties { RedirectUri = callbackUrl };
        return Challenge(props, KeycloakAuthenticationDefaults.AuthenticationScheme);
    }

    /// <summary>
    /// Receives the OIDC callback, extracts claims, and delegates to nopCommerce's
    /// <see cref="IExternalAuthenticationService.AuthenticateAsync"/> to create/link the customer.
    /// </summary>
    public async Task<IActionResult> LoginCallback(string returnUrl)
    {
        var authResult = await HttpContext.AuthenticateAsync(KeycloakAuthenticationDefaults.AuthenticationScheme);
        if (!authResult.Succeeded || authResult.Principal?.Claims.Any() != true)
            return RedirectToRoute("Login");

        var principal = authResult.Principal;

        // Keycloak OIDC uses "sub" as the stable unique identifier; "email" for the user email.
        var externalId   = principal.FindFirstValue(ClaimTypes.NameIdentifier)
                        ?? principal.FindFirstValue("sub");
        var email        = principal.FindFirstValue(ClaimTypes.Email)
                        ?? principal.FindFirstValue("email");
        var firstName    = principal.FindFirstValue(ClaimTypes.GivenName)
                        ?? principal.FindFirstValue("given_name");
        var lastName     = principal.FindFirstValue(ClaimTypes.Surname)
                        ?? principal.FindFirstValue("family_name");
        var displayName  = principal.FindFirstValue(ClaimTypes.Name)
                        ?? principal.FindFirstValue("preferred_username")
                        ?? string.Join(' ', new[] { firstName, lastName }.Where(v => !string.IsNullOrWhiteSpace(v)))
                        ?? email;

        var claims = principal.Claims
            .Select(c => new ExternalAuthenticationClaim(c.Type, c.Value))
            .ToList();

        AddClaimIfMissing(claims, ClaimTypes.GivenName, firstName);
        AddClaimIfMissing(claims, ClaimTypes.Surname, lastName);
        AddClaimIfMissing(claims, ClaimTypes.Email, email);
        AddClaimIfMissing(claims, ClaimTypes.Name, displayName);

        var authParams = new ExternalAuthenticationParameters
        {
            ProviderSystemName        = KeycloakAuthenticationDefaults.ProviderSystemName,
            AccessToken               = await HttpContext.GetTokenAsync(
                                            KeycloakAuthenticationDefaults.AuthenticationScheme, "access_token"),
            Email                     = email,
            ExternalIdentifier        = externalId,
            ExternalDisplayIdentifier = displayName,
            Claims                    = claims
        };

        var associatedCustomer = await _externalAuthenticationService.GetUserByExternalAuthenticationParametersAsync(authParams);
        if (associatedCustomer != null)
        {
            var changed = false;

            if (!string.IsNullOrWhiteSpace(firstName) && !string.Equals(associatedCustomer.FirstName, firstName, StringComparison.Ordinal))
            {
                associatedCustomer.FirstName = firstName;
                changed = true;
            }

            if (!string.IsNullOrWhiteSpace(lastName) && !string.Equals(associatedCustomer.LastName, lastName, StringComparison.Ordinal))
            {
                associatedCustomer.LastName = lastName;
                changed = true;
            }

            if (changed)
                await _customerService.UpdateCustomerAsync(associatedCustomer);
        }

        return await _externalAuthenticationService.AuthenticateAsync(authParams, returnUrl);
    }

    private static void AddClaimIfMissing(ICollection<ExternalAuthenticationClaim> claims, string type, string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || claims.Any(c => c.Type == type))
            return;

        claims.Add(new ExternalAuthenticationClaim(type, value));
    }
}

