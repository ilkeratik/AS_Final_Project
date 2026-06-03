using Federation.MeilisearchIndexer.Workers;
using Meilisearch;

var host = Host.CreateDefaultBuilder(args)
    .ConfigureServices((ctx, services) =>
    {
        var cfg = ctx.Configuration;
        var meiliUrl    = cfg["Meilisearch:Url"]    ?? "http://meilisearch:7700";
        var meiliKey    = cfg["Meilisearch:ApiKey"]  ?? "";
        var kafka       = cfg["Kafka:BootstrapServers"] ?? "kafka:9092";
        var groupId     = cfg["Kafka:ConsumerGroupId"]  ?? "federation-indexer";
        var topic       = cfg["Kafka:Topic"]            ?? "federation.products";

        var meiliClient = new MeilisearchClient(meiliUrl, meiliKey);
        services.AddSingleton(meiliClient);
        services.AddHostedService(sp =>
            new IndexerWorker(kafka, groupId, topic,
                sp.GetRequiredService<MeilisearchClient>(),
                sp.GetRequiredService<ILogger<IndexerWorker>>()));
    })
    .Build();

await host.RunAsync();

