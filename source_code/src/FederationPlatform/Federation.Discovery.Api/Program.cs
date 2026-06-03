using Meilisearch;

var builder = WebApplication.CreateBuilder(args);

var meiliUrl = builder.Configuration["Meilisearch:Url"]    ?? "http://meilisearch:7700";
var meiliKey = builder.Configuration["Meilisearch:ApiKey"] ?? "";

builder.Services.AddSingleton(_ => new MeilisearchClient(meiliUrl, meiliKey));
builder.Services.AddOpenApi();
builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
    p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

// Output cache: short TTL avoids hammering Meilisearch on repeated identical queries.
builder.Services.AddOutputCache(opt =>
{
    opt.AddPolicy("search", p => p.Cache().Expire(TimeSpan.FromSeconds(1))
        .SetVaryByQuery("q", "stores", "page", "pageSize", "sort"));
    opt.AddPolicy("facets", p => p.Cache().Expire(TimeSpan.FromSeconds(5))
        .SetVaryByQuery("q"));
});

var app = builder.Build();
app.UseCors();
app.UseOutputCache();
app.MapOpenApi();

// ── Health ───────────────────────────────────────────────────────────────────
app.MapGet("/health", () => Results.Ok(new { status = "healthy", utc = DateTime.UtcNow }))
   .WithName("Health");

// ── Federated product search ──────────────────────────────────────────────────
// GET /api/search?q=laptop&stores=bu-a,bu-b&page=0&pageSize=20&sort=price:asc
app.MapGet("/api/search", async (
    MeilisearchClient meili,
    string? q,
    string? stores,
    string? sort,
    int page     = 0,
    int pageSize = 20) =>
{
    if (string.IsNullOrWhiteSpace(q))
        return Results.BadRequest(new { error = "Query parameter 'q' is required." });

    pageSize = Math.Clamp(pageSize, 1, 100);
    var index = meili.Index("products");

    var searchQuery = new SearchQuery
    {
        Limit  = pageSize,
        Offset = page * pageSize,
        AttributesToHighlight = ["productName", "shortDescription"]
    };

    // Sort: accepts "price:asc", "price:desc", "publishedAt:desc"
    if (!string.IsNullOrWhiteSpace(sort))
        searchQuery.Sort = [sort];

    if (!string.IsNullOrWhiteSpace(stores))
    {
        var codes = stores.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (codes.Length > 0)
            searchQuery.Filter = string.Join(" OR ", codes.Select(c => $"storeCode = \"{c}\""));
    }

    var result    = await index.SearchAsync<ProductHit>(q, searchQuery);
    int? estimated = (result as SearchResult<ProductHit>)?.EstimatedTotalHits;

    return Results.Ok(new SearchResponse(
        Query:     q,
        TotalHits: estimated ?? result.Hits.Count,
        Page:      page,
        PageSize:  pageSize,
        Hits:      result.Hits.Select(SearchHit.FromProductHit).ToList()
    ));
})
.WithName("SearchProducts")
.CacheOutput("search");

// ── Facets (store + category distribution) ───────────────────────────────────
// GET /api/facets?q=laptop
app.MapGet("/api/facets", async (MeilisearchClient meili, string? q) =>
{
    var index = meili.Index("products");

    var searchQuery = new SearchQuery
    {
        Limit  = 0,
        Facets = ["storeCode", "categories"]
    };

    var result     = await index.SearchAsync<ProductHit>(q ?? "", searchQuery);
    var storeCodes = result.FacetDistribution?.GetValueOrDefault("storeCode") ?? new Dictionary<string, int>();

    // Resolve store names in parallel — one query per store code, run concurrently.
    var nameTasksByCode = storeCodes.Keys
        .ToDictionary(
            code => code,
            code => index.SearchAsync<ProductHit>("", new SearchQuery { Limit = 1, Filter = $"storeCode = \"{code}\"" }));

    await Task.WhenAll(nameTasksByCode.Values);

    var storesWithNames = storeCodes.ToDictionary(
        kvp => kvp.Key,
        kvp => (object)new
        {
            count = kvp.Value,
            name  = nameTasksByCode[kvp.Key].Result.Hits.FirstOrDefault()?.StoreName ?? kvp.Key
        });

    return Results.Ok(new
    {
        stores     = storesWithNames,
        categories = result.FacetDistribution?.GetValueOrDefault("categories")
                     ?? new Dictionary<string, int>()
    });
})
.WithName("Facets")
.CacheOutput("facets");

await app.RunAsync();

// ── Response records ──────────────────────────────────────────────────────────

record SearchResponse(string Query, int TotalHits, int Page, int PageSize, IReadOnlyList<SearchHit> Hits);

record SearchHit(
    string   Id,
    string   StoreCode,
    string   StoreName,
    int      ProductId,
    string   ProductName,
    string   ShortDescription,
    decimal  Price,
    string?  ThumbnailUrl,
    string?  ProductUrl,
    string?  Slug,
    IReadOnlyList<string> Categories,
    DateTime PublishedAt)
{
    public static SearchHit FromProductHit(ProductHit h) => new(
        h.Id, h.StoreCode, h.StoreName, h.ProductId,
        h.ProductName, h.ShortDescription, h.Price,
        h.ThumbnailUrl, h.ProductUrl, h.Slug,
        h.Categories, h.PublishedAt);
}

// ── Meilisearch document model ────────────────────────────────────────────────
sealed class ProductHit
{
    public string Id { get; set; } = string.Empty;
    public string StoreCode { get; set; } = string.Empty;
    public string StoreName { get; set; } = string.Empty;
    public int ProductId { get; set; }
    public string ProductName { get; set; } = string.Empty;
    public string ShortDescription { get; set; } = string.Empty;
    public decimal Price { get; set; }
    public string? ThumbnailUrl { get; set; }
    public string? ProductUrl { get; set; }
    public string? Slug { get; set; }
    public List<string> Categories { get; set; } = [];
    public DateTime PublishedAt { get; set; }
}