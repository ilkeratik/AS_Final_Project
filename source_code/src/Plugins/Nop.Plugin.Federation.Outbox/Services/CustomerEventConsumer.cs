using Newtonsoft.Json;
using Nop.Core.Domain.Customers;
using Nop.Core.Events;
using Nop.Services.Events;
using Nop.Services.Logging;
using Nop.Plugin.Federation.Outbox.Domain;

namespace Nop.Plugin.Federation.Outbox.Services;

/// <summary>
/// Listens to nopCommerce customer registration events and writes them to the outbox table.
/// Settings served from <see cref="IOutboxSettingsCache"/> (Singleton, 60 s TTL).
/// Downstream: Group CRM (EspoCRM) + Keycloak SSO — see §6.3 and diagram 8.3.
/// Guests (no email) and system accounts are filtered out.
/// </summary>
public class CustomerEventConsumer :
    IConsumer<EntityInsertedEvent<Customer>>,
    IConsumer<EntityUpdatedEvent<Customer>>
{
    private readonly IOutboxService       _outboxService;
    private readonly IOutboxSettingsCache _settingsCache;
    private readonly ILogger              _logger;

    public CustomerEventConsumer(
        IOutboxService outboxService,
        IOutboxSettingsCache settingsCache,
        ILogger logger)
    {
        _outboxService = outboxService;
        _settingsCache = settingsCache;
        _logger        = logger;
    }

    public async Task HandleEventAsync(EntityInsertedEvent<Customer> eventMessage)
        => await EnqueueAsync(eventMessage.Entity, FederationOutboxDefaults.EventTypes.CustomerCreated);

    public async Task HandleEventAsync(EntityUpdatedEvent<Customer> eventMessage)
        => await EnqueueAsync(eventMessage.Entity, FederationOutboxDefaults.EventTypes.CustomerUpdated);

    private async Task EnqueueAsync(Customer customer, string eventType)
    {
        try
        {
            // Only publish registered customers with a stable identity.
            if (customer.IsSystemAccount || string.IsNullOrWhiteSpace(customer.Email))
                return;

            var settings = await _settingsCache.GetAsync();
            if (!settings.Enabled || string.IsNullOrEmpty(settings.StoreCode))
                return;

            var (msgId, correlationId, now) = OutboxMessage.NewContext(settings.StoreCode, eventType, customer.Id);

            var payload = new
            {
                messageId     = msgId,
                correlationId,
                storeCode     = settings.StoreCode,
                storeName     = settings.StoreName,
                eventType,
                customerId    = customer.Id,
                customerGuid  = customer.CustomerGuid,
                email         = customer.Email,
                username      = customer.Username,
                occurredOnUtc = now
            };

            await _outboxService.EnqueueAsync(new OutboxMessage
            {
                MessageId     = msgId,
                CorrelationId = correlationId,
                StoreCode     = settings.StoreCode,
                StoreName     = settings.StoreName,
                EventType     = eventType,
                Topic         = FederationOutboxDefaults.CustomersTopic,
                Payload       = JsonConvert.SerializeObject(payload),
                CreatedOnUtc  = OutboxMessage.ToDatabaseTime(now),
                EntityId      = customer.Id
            });
        }
        catch (Exception ex)
        {
            await _logger.ErrorAsync(
                $"[Federation.Outbox] Failed to enqueue customer {customer.Id}: {ex.Message}", ex);
        }
    }
}
