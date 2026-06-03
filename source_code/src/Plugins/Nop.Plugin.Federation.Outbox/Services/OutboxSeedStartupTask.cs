using Newtonsoft.Json;
using Nop.Core;
using Nop.Core.Domain.Catalog;
using Nop.Services.Catalog;
using Nop.Services.Logging;
using Nop.Services.Media;
using Nop.Services.Seo;
using Nop.Plugin.Federation.Outbox.Domain;
using Microsoft.Extensions.Hosting;

namespace Nop.Plugin.Federation.Outbox.Services;

/// <summary>
/// Runs once after application startup and enqueues missing published products into outbox.
/// Hosted service is DI-friendly and avoids IStartupTask's parameterless-constructor restriction.
/// </summary>
public class OutboxSeedHostedService : BackgroundService
{
    private const int PageSize = 200;

    private readonly IOutboxService       _outboxService;
    private readonly IOutboxSettingsCache _settingsCache;
    private readonly IProductService      _productService;
    private readonly IUrlRecordService    _urlRecordService;
    private readonly IPictureService      _pictureService;
    private readonly ICategoryService     _categoryService;
    private readonly ILogger              _logger;

    public OutboxSeedHostedService(
        IOutboxService outboxService,
        IOutboxSettingsCache settingsCache,
        IProductService productService,
        IUrlRecordService urlRecordService,
        IPictureService pictureService,
        ICategoryService categoryService,
        ILogger logger)
    {
        _outboxService    = outboxService;
        _settingsCache    = settingsCache;
        _productService   = productService;
        _urlRecordService = urlRecordService;
        _pictureService   = pictureService;
        _categoryService  = categoryService;
        _logger           = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Give nopCommerce boot sequence a short head-start before reading settings and catalog data.
        await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);

        FederationOutboxSettings settings;
        try
        {
            settings = await _settingsCache.GetAsync();
        }
        catch (Exception ex)
        {
            await _logger.WarningAsync("[Federation.Outbox] Seed hosted service: could not load settings, skipping.", ex);
            return;
        }

        if (!settings.Enabled || string.IsNullOrWhiteSpace(settings.StoreCode))
            return;

        if (!await _outboxService.HasAnyAsync())
        {
            await _logger.InformationAsync(
                $"[Federation.Outbox] Fresh install detected for store '{settings.StoreCode}'; skipping bootstrap product population.");
            return;
        }

        await _logger.InformationAsync($"[Federation.Outbox] Checking published products for store '{settings.StoreCode}'…");

        var seeded = 0;
        var skipped = 0;
        var pageIndex = 0;

        while (!stoppingToken.IsCancellationRequested)
        {
            IPagedList<Product> page;
            try
            {
                page = await _productService.SearchProductsAsync(
                    pageIndex: pageIndex,
                    pageSize: PageSize,
                    overridePublished: true);
            }
            catch (Exception ex)
            {
                await _logger.ErrorAsync($"[Federation.Outbox] Seed hosted service failed loading products (page {pageIndex}).", ex);
                break;
            }

            foreach (var product in page)
            {
                if (stoppingToken.IsCancellationRequested)
                    break;

                if (product.Deleted)
                    continue;

                try
                {
                    if (await _outboxService.HasBeenEnqueuedAsync(settings.StoreCode, product.Id))
                    {
                        skipped++;
                        continue;
                    }

                    var (msgId, correlationId, now) = OutboxMessage.NewContext(
                        settings.StoreCode, FederationOutboxDefaults.EventTypes.Published, product.Id);

                    var slug       = await GetSlugAsync(product);
                    var thumbUrl   = await GetThumbnailUrlAsync(product);
                    var categories = await GetCategoryNamesAsync(product.Id);

                    var payload = new
                    {
                        messageId        = msgId,
                        correlationId,
                        storeCode        = settings.StoreCode,
                        storeName        = settings.StoreName,
                        eventType        = FederationOutboxDefaults.EventTypes.Published,
                        productId        = product.Id,
                        productName      = product.Name,
                        shortDescription = product.ShortDescription,
                        price            = product.Price,
                        thumbnailUrl     = thumbUrl,
                        productUrl       = BuildProductUrl(slug, settings.StorefrontBaseUrl),
                        slug,
                        categories,
                        occurredOnUtc    = now
                    };

                    await _outboxService.EnqueueAsync(new OutboxMessage
                    {
                        MessageId     = msgId,
                        CorrelationId = correlationId,
                        StoreCode     = settings.StoreCode,
                        StoreName     = settings.StoreName,
                        EventType     = FederationOutboxDefaults.EventTypes.Published,
                        Topic         = FederationOutboxDefaults.KafkaTopic,
                        Payload       = JsonConvert.SerializeObject(payload),
                        CreatedOnUtc  = OutboxMessage.ToDatabaseTime(now),
                        EntityId      = product.Id
                    });

                    seeded++;
                }
                catch (Exception ex)
                {
                    await _logger.WarningAsync($"[Federation.Outbox] Seed hosted service skipped product {product.Id}: {ex.Message}", ex);
                }
            }

            if (!page.HasNextPage)
                break;

            pageIndex++;
        }

        await _logger.InformationAsync(
            $"[Federation.Outbox] Seed complete for '{settings.StoreCode}': {seeded} new product(s), {skipped} already published.");
    }

    private async Task<string?> GetSlugAsync(Product product)
    {
        try { return await _urlRecordService.GetSeNameAsync(product); }
        catch { return null; }
    }

    private async Task<string?> GetThumbnailUrlAsync(Product product)
    {
        try
        {
            var pics = await _pictureService.GetPicturesByProductIdAsync(product.Id, 1);
            var pic = pics.FirstOrDefault();
            return pic is null ? null : (await _pictureService.GetPictureUrlAsync(pic, 415)).Url;
        }
        catch { return null; }
    }

    private async Task<List<string>> GetCategoryNamesAsync(int productId)
    {
        try
        {
            var mappings = await _categoryService.GetProductCategoriesByProductIdAsync(productId);
            var cats = await Task.WhenAll(mappings.Select(m => _categoryService.GetCategoryByIdAsync(m.CategoryId)));
            return cats.Where(c => c is { Deleted: false })
                       .Select(c => c!.Name)
                       .ToList();
        }
        catch { return []; }
    }

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
