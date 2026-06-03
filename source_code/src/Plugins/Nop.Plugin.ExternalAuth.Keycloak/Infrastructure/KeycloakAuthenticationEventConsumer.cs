using System.Security.Claims;
using Nop.Services.Authentication.External;
using Nop.Services.Customers;
using Nop.Services.Events;

namespace Nop.Plugin.ExternalAuth.Keycloak.Infrastructure;

/// <summary>
/// Saves first/last name from Keycloak claims when nopCommerce auto-registers
/// a new customer through external authentication.
/// </summary>
public class KeycloakAuthenticationEventConsumer : IConsumer<CustomerAutoRegisteredByExternalMethodEvent>
{
    private readonly ICustomerService _customerService;

    public KeycloakAuthenticationEventConsumer(ICustomerService customerService)
    {
        _customerService = customerService;
    }

    public async Task HandleEventAsync(CustomerAutoRegisteredByExternalMethodEvent eventMessage)
    {
        if (eventMessage?.Customer == null || eventMessage.AuthenticationParameters == null)
            return;

        if (!eventMessage.AuthenticationParameters.ProviderSystemName.Equals(
                KeycloakAuthenticationDefaults.ProviderSystemName, StringComparison.OrdinalIgnoreCase))
            return;

        var customer = eventMessage.Customer;
        var claims = eventMessage.AuthenticationParameters.Claims;

        var firstName = claims?.FirstOrDefault(claim => claim.Type == ClaimTypes.GivenName)?.Value
                     ?? claims?.FirstOrDefault(claim => claim.Type == "given_name")?.Value;
        if (!string.IsNullOrWhiteSpace(firstName))
            customer.FirstName = firstName;

        var lastName = claims?.FirstOrDefault(claim => claim.Type == ClaimTypes.Surname)?.Value
                    ?? claims?.FirstOrDefault(claim => claim.Type == "family_name")?.Value;
        if (!string.IsNullOrWhiteSpace(lastName))
            customer.LastName = lastName;

        if (!string.IsNullOrWhiteSpace(firstName) || !string.IsNullOrWhiteSpace(lastName))
            await _customerService.UpdateCustomerAsync(customer);
    }
}

