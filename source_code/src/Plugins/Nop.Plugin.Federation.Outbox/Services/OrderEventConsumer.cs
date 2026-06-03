using Newtonsoft.Json;
using Nop.Core.Domain.Orders;
using Nop.Core.Events;
using Nop.Services.Events;
using Nop.Services.Logging;
using Nop.Plugin.Federation.Outbox.Domain;

namespace Nop.Plugin.Federation.Outbox.Services;

/// <summary>
/// Listens to nopCommerce order lifecycle events and writes them to the outbox table.
/// Settings served from <see cref="IOutboxSettingsCache"/> (Singleton, 60 s TTL).
/// Satisfies QA Scenario 1 (Fault Containment / ADR-2 / §8.5 Order Flow).
/// </summary>
public class OrderEventConsumer :
    IConsumer<EntityInsertedEvent<Order>>,
    IConsumer<EntityUpdatedEvent<Order>>
{
    private readonly IOutboxService       _outboxService;
    private readonly IOutboxSettingsCache _settingsCache;
    private readonly ILogger              _logger;

    public OrderEventConsumer(
        IOutboxService outboxService,
        IOutboxSettingsCache settingsCache,
        ILogger logger)
    {
        _outboxService = outboxService;
        _settingsCache = settingsCache;
        _logger        = logger;
    }

    public async Task HandleEventAsync(EntityInsertedEvent<Order> eventMessage)
        => await EnqueueAsync(eventMessage.Entity, FederationOutboxDefaults.EventTypes.OrderPlaced);

    public async Task HandleEventAsync(EntityUpdatedEvent<Order> eventMessage)
    {
        var order     = eventMessage.Entity;
        var eventType = order.OrderStatus == OrderStatus.Cancelled
            ? FederationOutboxDefaults.EventTypes.OrderCancelled
            : FederationOutboxDefaults.EventTypes.OrderUpdated;
        await EnqueueAsync(order, eventType);
    }

    private async Task EnqueueAsync(Order order, string eventType)
    {
        try
        {
            var settings = await _settingsCache.GetAsync();
            if (!settings.Enabled || string.IsNullOrEmpty(settings.StoreCode))
                return;

            var (msgId, correlationId, now) = OutboxMessage.NewContext(settings.StoreCode, eventType, order.Id);

            var payload = new
            {
                messageId               = msgId,
                correlationId,
                storeCode               = settings.StoreCode,
                storeName               = settings.StoreName,
                eventType,
                orderId                 = order.Id,
                orderGuid               = order.OrderGuid,
                customerId              = order.CustomerId,
                orderTotal              = order.OrderTotal,
                currencyCode            = order.CustomerCurrencyCode,
                paymentMethodSystemName = order.PaymentMethodSystemName,
                orderStatus             = (int)order.OrderStatus,
                occurredOnUtc           = now
            };

            await _outboxService.EnqueueAsync(new OutboxMessage
            {
                MessageId     = msgId,
                CorrelationId = correlationId,
                StoreCode     = settings.StoreCode,
                StoreName     = settings.StoreName,
                EventType     = eventType,
                Topic         = FederationOutboxDefaults.OrdersTopic,
                Payload       = JsonConvert.SerializeObject(payload),
                CreatedOnUtc  = OutboxMessage.ToDatabaseTime(now),
                EntityId      = order.Id
            });
        }
        catch (Exception ex)
        {
            await _logger.ErrorAsync(
                $"[Federation.Outbox] Failed to enqueue order {order.Id}: {ex.Message}", ex);
        }
    }
}
