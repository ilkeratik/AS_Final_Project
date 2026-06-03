using Newtonsoft.Json;
using Nop.Core.Domain.Catalog;
using Nop.Core.Events;
using Nop.Services.Catalog;
using Nop.Services.Events;
using Nop.Services.Logging;
using Nop.Services.Media;
using Nop.Services.Seo;
using Nop.Plugin.Federation.Outbox.Domain;

namespace Nop.Plugin.Federation.Outbox.Services;

/// <summary>
/// Listens to nopCommerce product lifecycle events and writes them to the outbox table.
/// Settings are served from <see cref="IOutboxSettingsCache"/> (Singleton, 60 s TTL).
/// Categories are fetched in parallel via <c>Task.WhenAll</c>.
/// </summary>
public class ProductEventConsumer :
    IConsumer<EntityInsertedEvent<Product>>,
    IConsumer<EntityUpdatedEvent<Product>>,
    IConsumer<EntityDeletedEvent<Product>>
{
    private readonly IOutboxService        _outboxService;
    private readonly IOutboxSettingsCache  _settingsCache;
    private readonly ICategoryService      _categoryService;
    private readonly IPictureService       _pictureService;
    private readonly IUrlRecordService     _urlRecordService;
    private readonly ILogger               _logger;

    public ProductEventConsumer(
        IOutboxService outboxService,
        IOutboxSettingsCache settingsCache,
        ICategoryService categoryService,
        IPictureService pictureService,
        IUrlRecordService urlRecordService,
        ILogger logger)
    {
        _outboxService    = outboxService;
        _settingsCache    = settingsCache;
        _categoryService  = categoryService;
        _pictureService   = pictureService;
        _urlRecordService = urlRecordService;
        _logger           = logger;
    }

    public async Task HandleEventAsync(EntityInsertedEvent<Product> eventMessage)
    {
        var p = eventMessage.Entity;
        await EnqueueAsync(p, p.Published
            ? FederationOutboxDefaults.EventTypes.Published
            : FederationOutboxDefaults.EventTypes.Unpublished);
    }

    public async Task HandleEventAsync(EntityUpdatedEvent<Product> eventMessage)
    {
        var p = eventMessage.Entity;
        await EnqueueAsync(p, p.Deleted
            ? FederationOutboxDefaults.EventTypes.Deleted
            : p.Published
                ? FederationOutboxDefaults.EventTypes.Updated
                : FederationOutboxDefaults.EventTypes.Unpublished);
    }

    public async Task HandleEventAsync(EntityDeletedEvent<Product> eventMessage)
        => await EnqueueAsync(eventMessage.Entity, FederationOutboxDefaults.EventTypes.Deleted);

    // ── helpers ──────────────────────────────────────────────────────────────

    private async Task EnqueueAsync(Product product, string eventType)
    {
        try
        {
            var settings = await _settingsCache.GetAsync();
            if (!settings.Enabled || string.IsNullOrEmpty(settings.StoreCode))
                return;

            if (eventType is FederationOutboxDefaults.EventTypes.Deleted
                          or FederationOutboxDefaults.EventTypes.Unpublished)
            {
                var alreadyEnqueued = await _outboxService.HasEventEnqueuedAsync(settings.StoreCode, product.Id, eventType);
                if (alreadyEnqueued)
                    return;
            }

            await _logger.InformationAsync(
                $"[Federation.Outbox] Product {product.Id} captured as {eventType} (published={product.Published}, deleted={product.Deleted}).");

            var (msgId, correlationId, now) = OutboxMessage.NewContext(settings.StoreCode, eventType, product.Id);

            // Fast path for removal events: the indexer only needs storeCode + productId to
            // compute the document ID — skip expensive / potentially-unavailable metadata
            // (nopCommerce may have already cascade-deleted pictures, categories, URL records).
            object payload;
            if (eventType is FederationOutboxDefaults.EventTypes.Deleted
                          or FederationOutboxDefaults.EventTypes.Unpublished)
            {
                payload = new
                {
                    messageId     = msgId,
                    correlationId,
                    storeCode     = settings.StoreCode,
                    storeName     = settings.StoreName,
                    eventType,
                    productId     = product.Id,
                    occurredOnUtc = now
                };
            }
            else
            {
                // Parallel: fetch categories + thumbnail + slug concurrently
                var categoriesTask = GetCategoryNamesAsync(product.Id);
                var thumbTask      = GetThumbnailUrlAsync(product);
                var slugTask       = GetSlugAsync(product);
                await Task.WhenAll(categoriesTask, thumbTask, slugTask);

                payload = new
                {
                    messageId        = msgId,
                    correlationId,
                    storeCode        = settings.StoreCode,
                    storeName        = settings.StoreName,
                    eventType,
                    productId        = product.Id,
                    productName      = product.Name,
                    shortDescription = product.ShortDescription,
                    price            = product.Price,
                    thumbnailUrl     = thumbTask.Result,
                    productUrl       = BuildProductUrl(slugTask.Result, settings.StorefrontBaseUrl),
                    slug             = slugTask.Result,
                    categories       = categoriesTask.Result,
                    occurredOnUtc    = now
                };
            }

            await _outboxService.EnqueueAsync(new OutboxMessage
            {
                MessageId     = msgId,
                CorrelationId = correlationId,
                StoreCode     = settings.StoreCode,
                StoreName     = settings.StoreName,
                EventType     = eventType,
                Topic         = FederationOutboxDefaults.KafkaTopic,
                Payload       = JsonConvert.SerializeObject(payload),
                CreatedOnUtc  = OutboxMessage.ToDatabaseTime(now),
                EntityId      = product.Id
            });
        }
        catch (Exception ex)
        {
            await _logger.ErrorAsync(
                $"[Federation.Outbox] Failed to enqueue product {product.Id}: {ex.Message}", ex);
        }
    }

    // Parallel category lookup — nopCommerce caches by ID so concurrent awaits hit the cache.
    private async Task<List<string>> GetCategoryNamesAsync(int productId)
    {
        try
        {
            var mappings = await _categoryService.GetProductCategoriesByProductIdAsync(productId);
            var cats = await Task.WhenAll(mappings.Select(m =>
                _categoryService.GetCategoryByIdAsync(m.CategoryId)));
            return cats.Where(c => c is { Deleted: false })
                       .Select(c => c!.Name)
                       .ToList();
        }
        catch { return []; }
    }

    private async Task<string?> GetThumbnailUrlAsync(Product product)
    {
        try
        {
            var pics = await _pictureService.GetPicturesByProductIdAsync(product.Id, 1);
            var pic  = pics.FirstOrDefault();
            return pic is null ? null : (await _pictureService.GetPictureUrlAsync(pic, 415)).Url;
        }
        catch { return null; }
    }

    private async Task<string?> GetSlugAsync(Product product)
    {
        try
        {
            return await _urlRecordService.GetSeNameAsync(product);
        }
        catch { return null; }
    }

    /// <summary>
    /// Builds an absolute product URL when <paramref name="storefrontBaseUrl"/> is set,
    /// or a root-relative path otherwise. Never returns a numeric /product/{id} route.
    /// </summary>
    private static string? BuildProductUrl(string? slug, string? storefrontBaseUrl)
    {
        if (string.IsNullOrWhiteSpace(slug))
            return null;

        var path = slug.Trim().Trim('/');
        return !string.IsNullOrWhiteSpace(storefrontBaseUrl)
            ? $"{storefrontBaseUrl.TrimEnd('/')}/{path}"
            : $"/{path}";
    }
}