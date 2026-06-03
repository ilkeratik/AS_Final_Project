using Newtonsoft.Json;
using Nop.Core.Domain.Catalog;
using Nop.Core.Domain.Logging;
using Nop.Core.Events;
using Nop.Data;
using Nop.Plugin.Federation.Outbox.Domain;
using Nop.Services.Events;
using Nop.Services.Logging;

namespace Nop.Plugin.Federation.Outbox.Services;

/// <summary>
/// Fallback delete capture: when a product is deleted from admin, nopCommerce writes an ActivityLog
/// row with SystemKeyword=DeleteProduct and EntityName=Product. This consumer converts that signal
/// into a product.deleted outbox event if one is not already present.
/// </summary>
public class ProductDeleteActivityLogConsumer : IConsumer<EntityInsertedEvent<ActivityLog>>
{
    private readonly IOutboxService _outboxService;
    private readonly IOutboxSettingsCache _settingsCache;
    private readonly IRepository<ActivityLogType> _activityLogTypeRepository;
    private readonly ILogger _logger;

    public ProductDeleteActivityLogConsumer(
        IOutboxService outboxService,
        IOutboxSettingsCache settingsCache,
        IRepository<ActivityLogType> activityLogTypeRepository,
        ILogger logger)
    {
        _outboxService = outboxService;
        _settingsCache = settingsCache;
        _activityLogTypeRepository = activityLogTypeRepository;
        _logger = logger;
    }

    public async Task HandleEventAsync(EntityInsertedEvent<ActivityLog> eventMessage)
    {
        var activity = eventMessage.Entity;
        if (activity.EntityId is null || activity.EntityId <= 0)
            return;

        if (!string.Equals(activity.EntityName, nameof(Product), StringComparison.OrdinalIgnoreCase))
            return;

        try
        {
            var activityType = await _activityLogTypeRepository.GetByIdAsync(activity.ActivityLogTypeId, cache => default);
            if (!string.Equals(activityType?.SystemKeyword, "DeleteProduct", StringComparison.OrdinalIgnoreCase))
                return;

            var settings = await _settingsCache.GetAsync();
            if (!settings.Enabled || string.IsNullOrWhiteSpace(settings.StoreCode))
                return;

            if (await _outboxService.HasEventEnqueuedAsync(settings.StoreCode, activity.EntityId.Value, FederationOutboxDefaults.EventTypes.Deleted))
                return;

            var (msgId, correlationId, now) = OutboxMessage.NewContext(
                settings.StoreCode,
                FederationOutboxDefaults.EventTypes.Deleted,
                activity.EntityId.Value);

            var payload = new
            {
                messageId = msgId,
                correlationId,
                storeCode = settings.StoreCode,
                storeName = settings.StoreName,
                eventType = FederationOutboxDefaults.EventTypes.Deleted,
                productId = activity.EntityId.Value,
                occurredOnUtc = now
            };

            await _outboxService.EnqueueAsync(new OutboxMessage
            {
                MessageId = msgId,
                CorrelationId = correlationId,
                StoreCode = settings.StoreCode,
                StoreName = settings.StoreName,
                EventType = FederationOutboxDefaults.EventTypes.Deleted,
                Topic = FederationOutboxDefaults.KafkaTopic,
                Payload = JsonConvert.SerializeObject(payload),
                CreatedOnUtc = OutboxMessage.ToDatabaseTime(now),
                EntityId = activity.EntityId.Value
            });

            await _logger.InformationAsync(
                $"[Federation.Outbox] Fallback captured delete via ActivityLog for product {activity.EntityId.Value}.");
        }
        catch (Exception ex)
        {
            await _logger.ErrorAsync(
                $"[Federation.Outbox] Failed ActivityLog delete fallback for product {activity.EntityId}: {ex.Message}", ex);
        }
    }
}

