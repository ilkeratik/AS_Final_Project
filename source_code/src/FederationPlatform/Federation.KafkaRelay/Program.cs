using Federation.KafkaRelay.Workers;

var host = Host.CreateDefaultBuilder(args)
    .ConfigureServices((ctx, services) =>
    {
        var cfg = ctx.Configuration;

        var kafka        = cfg["Kafka:BootstrapServers"] ?? "kafka:9092";
        var meilisearch  = cfg["Meilisearch:Url"]        ?? "http://meilisearch:7700";

        // Register one RelayWorker per configured BU
        var bus = cfg.GetSection("BusinessUnits").GetChildren().ToList();
        foreach (var bu in bus)
        {
            var connStr   = bu["ConnectionString"]
                ?? throw new InvalidOperationException($"BU '{bu.Key}' missing ConnectionString");
            var storeCode = bu["StoreCode"]
                ?? throw new InvalidOperationException($"BU '{bu.Key}' missing StoreCode");

            // Use a factory so each worker captures its own config snapshot
            services.AddSingleton<IHostedService>(sp =>
                new RelayWorker(
                    connStr,
                    storeCode,
                    kafka,
                    meilisearch,
                    sp.GetRequiredService<ILogger<RelayWorker>>()));
        }
    })
    .Build();

await host.RunAsync();

