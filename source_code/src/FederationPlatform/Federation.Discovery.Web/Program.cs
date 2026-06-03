using Microsoft.AspNetCore.WebUtilities;

var builder = WebApplication.CreateBuilder(args);

var discoveryApiUrl = builder.Configuration["DiscoveryApi:Url"] ?? "http://discovery-api:8080";

// Named HttpClient with a 10-second timeout per attempt.
// Retry logic is applied inline in the proxy handlers (no extra package required).
builder.Services.AddHttpClient("discovery-api", client =>
{
    client.BaseAddress = new Uri(discoveryApiUrl);
    client.Timeout     = TimeSpan.FromSeconds(10);
    client.DefaultRequestHeaders.ConnectionClose = false; // keep-alive
});

var app = builder.Build();
app.UseDefaultFiles();
app.UseStaticFiles();

// ── Health ────────────────────────────────────────────────────────────────────
app.MapGet("/health", () => Results.Ok(new { status = "healthy", utc = DateTime.UtcNow }));

// ── Proxy: /api/search → Discovery API (with 3-attempt retry) ────────────────
app.MapGet("/api/search", async (
    IHttpClientFactory factory,
    string? q, string? stores, string? sort, int page = 0, int pageSize = 20) =>
{
    if (string.IsNullOrWhiteSpace(q))
        return Results.BadRequest(new { error = "Query parameter 'q' is required." });

    var qs = new Dictionary<string, string?>
    {
        ["q"] = q, ["page"] = page.ToString(), ["pageSize"] = pageSize.ToString()
    };
    if (!string.IsNullOrEmpty(stores)) qs["stores"] = stores;
    if (!string.IsNullOrEmpty(sort))   qs["sort"]   = sort;

    var url    = QueryHelpers.AddQueryString("/api/search", qs);
    var client = factory.CreateClient("discovery-api");
    var resp   = await RetryAsync(() => client.GetAsync(url));
    var body   = await resp.Content.ReadAsStringAsync();
    return Results.Content(body, "application/json", statusCode: (int)resp.StatusCode);
});

// ── Proxy: /api/facets → Discovery API (with 3-attempt retry) ────────────────
app.MapGet("/api/facets", async (IHttpClientFactory factory, string? q) =>
{
    var url    = string.IsNullOrEmpty(q) ? "/api/facets" : $"/api/facets?q={Uri.EscapeDataString(q)}";
    var client = factory.CreateClient("discovery-api");
    var resp   = await RetryAsync(() => client.GetAsync(url));
    var body   = await resp.Content.ReadAsStringAsync();
    return Results.Content(body, "application/json", statusCode: (int)resp.StatusCode);
});

await app.RunAsync();

// ── Retry helper: 3 attempts, exponential backoff 100/200/400 ms ─────────────
// Only retries transient gateway errors (502/503/504); any other response is
// surfaced to the caller immediately.
static async Task<HttpResponseMessage> RetryAsync(Func<Task<HttpResponseMessage>> action)
{
    const int maxAttempts = 3;
    for (var attempt = 0; ; attempt++)
    {
        var isLastAttempt = attempt >= maxAttempts - 1;
        try
        {
            var response   = await action();
            var isTransient = (int)response.StatusCode is 502 or 503 or 504;
            if (!isTransient || isLastAttempt)
                return response;
        }
        catch when (!isLastAttempt) { /* swallow transient connection errors */ }

        await Task.Delay(100 << attempt); // 100 ms, 200 ms, 400 ms …
    }
}
