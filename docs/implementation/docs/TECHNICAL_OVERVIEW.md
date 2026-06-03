# nopCommerce Federated Commerce — Technical Overview

*Last updated: 2026-06-03*

---

## 1. System Purpose

Two independent e-commerce Business Units (BU-A: **HomeStyle Living**, BU-B: **WorkForge Industrial**) run as completely isolated nopCommerce stores. A shared event backbone connects them: product catalog changes, orders, and customer registrations flow through a transactional outbox → Kafka → downstream consumers. A unified search index (Meilisearch) and a shared identity provider (Keycloak) complete the federation layer.

---

## 2. High-Level Architecture

```
BU-A (nopCommerce :5001)          BU-B (nopCommerce :5002)
  PostgreSQL-A :5433                PostgreSQL-B :5434
       │  OutboxMessage                   │  OutboxMessage
       │                                  │
       └──────────────── Kafka Relay ─────┘
                              │
                         Kafka :9092
                         (KRaft, no ZooKeeper)
                              │
                    ┌─────────┴──────────┐
                    │                    │
           Meilisearch Indexer      (future consumers)
                    │
             Meilisearch :7700
                    │
           Discovery API :5010
                    │
           Discovery Web :5011
           + Embedded widget (BU homepages)

SSO: Keycloak :8080  (realm: nop-federation)
Observability: Prometheus :9090 · Grafana :3000
```

**Key properties:**
- Each BU has its own database and nopCommerce process — complete failure isolation.
- No direct BU-to-BU calls; all integration is async via Kafka.
- Events are written to PostgreSQL in the same transaction as the domain change — no dual-write risk.

---

## 3. Modules and Components

### 3.1 `Nop.Plugin.Federation.Outbox` (nopCommerce plugin)

**Location:** `Plugins/Nop.Plugin.Federation.Outbox/`

The primary integration plugin. Installed into each BU's nopCommerce instance.

#### 3.1.1 `OutboxMessage` entity

```
OutboxMessage
├── MessageId       string UNIQUE     — idempotency key: {storeCode}.{eventType}.{entityId}.{ticks}
├── StoreCode       string            — "bu-a" | "bu-b"
├── StoreName       string            — human-readable
├── EventType       string            — one of the EventTypes constants
├── Topic           string            — Kafka topic name
├── Payload         text              — JSON event payload
├── CorrelationId   string?           — UUID for distributed tracing (X-Correlation-Id header)
├── EntityId        int?              — Product.Id / Order.Id / Customer.Id
├── CreatedOnUtc    datetime          — timestamp without time zone (Npgsql: Kind=Unspecified)
├── ProcessedOnUtc  datetime?         — NULL = pending; set by KafkaRelay on confirmed delivery
├── Attempts        int               — incremented on failure; rows with Attempts ≥ 5 are dead-lettered
└── LastError       varchar(2000)?    — last failure message
```

`OutboxMessage.NewContext(storeCode, eventType, entityId)` is the single factory that generates a stable `MessageId`, a fresh `CorrelationId` UUID, and a consistent UTC timestamp — used by all consumers to eliminate boilerplate.

`OutboxMessage.ToDatabaseTime(dt)` normalises `DateTimeKind` to `Unspecified` before writing to PostgreSQL `timestamp without time zone` columns (Npgsql 6+ rejects `DateTimeKind.Utc` for that column type).

#### 3.1.2 Event consumers

All three consumers implement nopCommerce's `IConsumer<T>` interface and fire inside the current unit-of-work, ensuring the outbox row is written **in the same database transaction** as the domain change.

| Consumer class | Listens to | Event types emitted | Kafka topic |
|---|---|---|---|
| `ProductEventConsumer` | `EntityInsertedEvent<Product>`, `EntityUpdatedEvent<Product>`, `EntityDeletedEvent<Product>` | `product.published`, `product.updated`, `product.unpublished`, `product.deleted` | `federation.products` |
| `OrderEventConsumer` | `EntityInsertedEvent<Order>`, `EntityUpdatedEvent<Order>` | `order.placed`, `order.updated`, `order.cancelled` | `orders.placed` |
| `CustomerEventConsumer` | `EntityInsertedEvent<Customer>`, `EntityUpdatedEvent<Customer>` | `customer.created`, `customer.updated` | `customers.created` |

**`ProductEventConsumer` logic in detail:**

1. On `EntityInsertedEvent<Product>`: emits `product.published` or `product.unpublished` based on `Product.Published`.
2. On `EntityUpdatedEvent<Product>`: emits `product.deleted` (if `Deleted=true`), `product.unpublished` (if `Published=false`), or `product.updated` otherwise.
3. On `EntityDeletedEvent<Product>`: always emits `product.deleted`.

**Fast path for removal events:** `product.deleted` and `product.unpublished` skip all metadata fetches (categories, thumbnail, slug) because nopCommerce may have already cascade-deleted those records. The indexer only needs `storeCode + productId` to compute the Meilisearch document ID.

**Publish/update path:** categories, thumbnail URL, and SEO slug are fetched concurrently via `Task.WhenAll`, then serialised into the JSON payload.

**Idempotency for deletes/unpublishes:** before writing, `IOutboxService.HasEventEnqueuedAsync` checks whether a matching row already exists, preventing duplicates when both direct product events and the activity-log fallback fire simultaneously.

#### 3.1.3 `ProductDeleteActivityLogConsumer` (fallback)

Listens to `EntityInsertedEvent<ActivityLog>`. When `ActivityLogType.SystemKeyword == "DeleteProduct"`, it enqueues a minimal `product.deleted` outbox row. This catches edge cases where the main product event consumer misses a deletion (e.g., bulk operations or soft-delete paths that bypass normal event firing).

#### 3.1.4 `OutboxService`

`IOutboxService` / `OutboxService` — the persistence layer for outbox operations:

| Method | Description |
|---|---|
| `EnqueueAsync(message)` | Idempotent insert — checks `MessageId` uniqueness before inserting |
| `HasAnyAsync()` | Used by seed service to detect fresh vs. existing install |
| `HasBeenEnqueuedAsync(storeCode, entityId)` | Checks if any row exists for this entity |
| `HasEventEnqueuedAsync(storeCode, entityId, eventType)` | Event-level deduplication |
| `GetPendingAsync(batchSize)` | Returns pending rows (used by seed diagnostics) |
| `MarkProcessedAsync(id)` | Set-based UPDATE on single row |
| `RecordFailureAsync(id, error)` | Increments Attempts, records LastError |
| `PurgeProcessedAsync(retainDays)` | Set-based DELETE of old processed rows |

#### 3.1.5 `OutboxSeedHostedService`

A `BackgroundService` that runs once after nopCommerce starts (5 s delay for boot):

1. Loads `FederationOutboxSettings` (StoreCode, StoreName, StorefrontBaseUrl, Enabled).
2. Calls `HasAnyAsync()` — if outbox table is **empty**, this is a fresh install and seeding is skipped entirely.
3. Otherwise, pages through all published products in batches of 200. For each product not already in the outbox, builds a full payload (slug + thumbnail + categories) and enqueues it as `product.published`.

This covers the restart / catch-up scenario: products created before the plugin was installed are automatically relayed.

#### 3.1.6 `FederationOutboxDefaults`

Central constants class:

```csharp
MaxAttempts = 5            // shared with KafkaRelay
KafkaTopic  = "federation.products"
OrdersTopic = "orders.placed"
CustomersTopic = "customers.created"

EventTypes.Published   = "product.published"
EventTypes.Updated     = "product.updated"
EventTypes.Unpublished = "product.unpublished"
EventTypes.Deleted     = "product.deleted"
EventTypes.OrderPlaced / OrderUpdated / OrderCancelled
EventTypes.CustomerCreated / CustomerUpdated
```

---

### 3.2 `Federation.KafkaRelay`

**Location:** `FederationPlatform/Federation.KafkaRelay/`

A standalone .NET `BackgroundService` host. One `RelayWorker` instance per BU is registered in `Program.cs`, each with its own PostgreSQL connection string and `storeCode`.

#### 3.2.1 Relay loop (every 5 s)

```
OPEN transaction
  SELECT Id, MessageId, Topic, EventType, EntityId, Payload, CorrelationId, Attempts
  FROM   OutboxMessage
  WHERE  ProcessedOnUtc IS NULL AND Attempts < 5
  ORDER  BY CreatedOnUtc
  LIMIT  50
  FOR UPDATE SKIP LOCKED        ← prevents concurrent relay workers from double-processing

for each row:
  log "[Relay:bu-x] Publishing outbox row {Id} ({EventType}) for entity {EntityId} to topic {Topic}"

  produce to Kafka:
    Key:     "{storeCode}.{messageId}"
    Value:   row.Payload (JSON)
    Headers: X-Store-Code, X-Message-Id, X-Correlation-Id

  if PersistenceStatus.Persisted:
    UPDATE OutboxMessage SET ProcessedOnUtc = NOW() WHERE Id = {row.Id}
    log "Kafka persisted row {Id} ({EventType})"
  else:
    UPDATE OutboxMessage SET Attempts = Attempts+1, LastError = status WHERE Id = {row.Id}
    log warning

COMMIT
log "[Relay:bu-x] Kafka relay batch committed. Published {N}, failed {M}."
```

**Producer config:** `Acks=All`, `EnableIdempotence=true`, `MessageSendMaxRetries=5` — guarantees at-least-once, ordered delivery per partition.

**Error handling:** On exception per row, `Attempts` is incremented. At `Attempts >= 5` the row is permanently skipped (dead-letter). The outer loop uses exponential backoff (base 5 s, cap 60 s, +random jitter up to 1 s) on consecutive batch-level errors.

#### 3.2.2 Meilisearch watchdog

Runs once after 30 s (let Meilisearch fully start), then every 5 minutes:

1. `GET /indexes/products/stats` — reads `numberOfDocuments`.
2. If `> 0`: index is healthy, skip.
3. If `== 0`: queries outbox for processed product rows.
   - If none exist → **fresh install**, skip.
   - If rows exist → Meilisearch data was wiped (container restart, volume wipe). Resets all processed product outbox rows (`ProcessedOnUtc = NULL, Attempts = 0`) so the relay re-publishes them, and the indexer rebuilds the index automatically within ~5 s. No manual intervention required.

---

### 3.3 `Federation.MeilisearchIndexer`

**Location:** `FederationPlatform/Federation.MeilisearchIndexer/`  
**Consumer group:** `federation-indexer`

#### 3.3.1 Startup

1. `EnsureIndexAsync()` — creates the `products` Meilisearch index (idempotent) and applies settings:
   - **Searchable attributes:** `productName`, `shortDescription`, `categories`, `storeName`, `slug`
   - **Filterable attributes:** `storeCode`, `categories`, `price`
   - **Sortable attributes:** `price`, `publishedAt`
   - **Ranking rules:** `words`, `typo`, `proximity`, `attribute`, `sort`, `exactness`
2. `EnsureTopicAvailableAsync()` — uses Kafka AdminClient to `CreateTopicsAsync` for `federation.products` (idempotent — ignores `TopicAlreadyExists`). Retries with exponential back-off up to ~2 minutes to handle Kafka startup race conditions.

#### 3.3.2 Batch consumption loop

```
while not cancelled:
  batch = DrainBatch(consumer)   ← collects up to 50 messages within a 500 ms window
  
  if batch.Count == 0: continue

  ProcessBatchAsync(batch):
    for each message:
      parse ProductChangedMessage from JSON
      docId = "{storeCode}-{productId}"     ← globally unique across all BUs

      if eventType in [product.deleted, product.unpublished]:
        deletes.Add(docId)
      else:
        upserts.Add(ToDocument(msg, docId))

    if upserts.Count > 0:
      index.AddDocumentsAsync(upserts, primaryKey: "id")   ← single bulk HTTP call

    if deletes.Count > 0:
      taskInfo = index.DeleteDocumentsAsync(deletes)
      finalTask = index.WaitForTaskAsync(taskInfo.TaskUid, timeout=10s)
      if finalTask.Status == Failed:
        DeleteDocumentsOneByOneAsync(deletes)   ← per-doc fallback with individual WaitForTask

  consumer.Commit(batch[^1])   ← commits the watermark offset once for the whole batch
```

`DrainBatch` uses short 50 ms poll timeouts within the 500 ms window so it exits promptly at the deadline. Non-fatal `ConsumeException` (e.g. rebalance in progress) returns an empty batch so the caller retries.

#### 3.3.3 Document model (`ProductDocument`)

```
id               = "{storeCode}-{productId}"   ← primary key
storeCode        = "bu-a" | "bu-b"
storeName        = "HomeStyle Living" | "WorkForge Industrial"
productId        int
productName      string
shortDescription string
price            decimal
thumbnailUrl     string?
productUrl       string?     — absolute slug URL (e.g. http://localhost:5001/armchair-velvet)
slug             string?
categories       string[]
publishedAt      datetime
```

---

### 3.4 `Federation.Discovery.Api`

**Location:** `FederationPlatform/Federation.Discovery.Api/` — port **5010**

Minimal ASP.NET Core Web API. Wraps Meilisearch queries over HTTP with output caching.

#### Endpoints

| Endpoint | Query params | Cache TTL | Description |
|---|---|---|---|
| `GET /api/search` | `q` (required), `stores` (comma-sep codes), `page` (default 0), `pageSize` (1–100), `sort` (`price:asc`, `price:desc`, `publishedAt:desc`) | **1 s** | Full-text + optionally store-filtered search. Returns `SearchResponse` with `totalHits`, pagination, and `hits` array. |
| `GET /api/facets` | `q` (optional) | **5 s** | Returns per-store hit counts and store names, plus category distribution. Uses Meilisearch facet search (`Limit=0`). |
| `GET /health` | — | — | `{ status: "healthy", utc: "..." }` |

**CORS:** `AllowAnyOrigin` so the embedded BU widget can call from different origins.

**`SearchHit` fields:** `id`, `storeCode`, `storeName`, `productId`, `productName`, `shortDescription`, `price`, `thumbnailUrl`, `productUrl`, `slug`, `categories`, `publishedAt`.

`productUrl` is always the absolute slug URL — the BU homepages and Discovery Web use this directly for deep links.

---

### 3.5 `Federation.Discovery.Web`

**Location:** `FederationPlatform/Federation.Discovery.Web/` — port **5011**

Standalone cross-brand search portal (HTML/CSS/JS). Features:
- Debounced search input.
- Store-filter chips populated from `/api/facets`.
- Price sort controls.
- "View ↗" deep links using `productUrl`.
- Auto-applies BU brand theme colours (BU-A blue / BU-B green).

---

### 3.6 `Federation.DiscoveryClient` (Embedded Widget)

**Location:** `FederationPlatform/Federation.DiscoveryClient/federated-search.js`

Vanilla ES6 module. Embedded on each BU's homepage via `Views/Home/_FederatedSearch.cshtml`. The partial sets `data-api-base` from the `FederatedSearch:ApiBase` configuration key (defaults to `http://localhost:5010`).

---

### 3.7 `Nop.Plugin.ExternalAuth.Keycloak` (SSO plugin)

**Location:** `Plugins/Nop.Plugin.ExternalAuth.Keycloak/`

#### Authentication flow

```
1. User clicks "Login with SSO"
   → GET /keycloakauthentication/login?returnUrl=...
   → Controller.Login() issues Challenge(AuthenticationScheme)
   → Browser redirects to Keycloak /authorize?client_id=bu-{a|b}-client

2. User authenticates on Keycloak
   → Keycloak redirects to /keycloakauthentication/callback  (OIDC middleware)
   → OIDC middleware exchanges code for id_token + access_token, stores in cookie
   → Middleware redirects to LoginCallback (the RedirectUri)

3. GET /keycloakauthentication/login-callback?returnUrl=...
   → Controller.LoginCallback()
   → HttpContext.AuthenticateAsync() reads claims from cookie
   → Maps: sub → ExternalIdentifier, email, given_name → FirstName, family_name → LastName
   → IExternalAuthenticationService.AuthenticateAsync() creates or links nopCommerce customer
   → If customer FirstName/LastName changed, UpdateCustomerAsync() is called
   → Redirected to returnUrl
```

**Two-route design** prevents OIDC session state loss: `/callback` is the OIDC middleware endpoint (preserves state cookie); `/login-callback` is the app-level MVC route that completes the nopCommerce sign-in.

**Per-BU settings:** `ClientId` differs (`bu-a-client` / `bu-b-client`); `Authority` and `MetadataAddress` point to the same Keycloak realm (`nop-federation`). A single Keycloak account works on both BU-A and BU-B.

---

### 3.8 Observability stack

**Location:** `monitoring/`

| Component | Port | Role |
|---|---|---|
| Prometheus | 9090 | Scrapes all exporters and Meilisearch native metrics |
| Grafana | 3000 | 3 auto-provisioned dashboards |
| Blackbox exporter | 9115 | HTTP probes for BU-A, BU-B, Discovery API/Web, Meilisearch |
| Postgres exporter BU-A | 9187 | Custom SQL → outbox metrics + event-type KPIs |
| Postgres exporter BU-B | 9188 | Same, for BU-B |

#### Custom outbox metrics (from `monitoring/postgres-exporter/queries.yaml`)

| Metric | Labels | Description |
|---|---|---|
| `federation_outbox_pending` | `bu` | Rows with `ProcessedOnUtc IS NULL` |
| `federation_outbox_processed` | `bu` | Rows with `ProcessedOnUtc IS NOT NULL` |
| `federation_outbox_deadletter` | `bu` | Rows with `Attempts >= 5` |
| `federation_outbox_total` | `bu` | All rows |
| `federation_outbox_oldest_pending_age_seconds` | `bu` | Age of oldest unprocessed row |
| `federation_outbox_events` | `bu`, `event_type` | Per-event-type counters (total/pending/processed/last_1h/last_24h) |
| `federation_activity_business` | `bu`, `action` | Business action volumes mapped from ActivityLog |

#### Grafana dashboards

| Dashboard | Primary story |
|---|---|
| **Federation Business Pulse** | Product create/update/delete volumes, order/customer event volumes |
| **Federation Demand Channels** | BU/discovery channel health, search request rate, search latency |
| **Federation Resilience and SLA** | Endpoint availability, outbox backlog/dead-letter/age, event delivery signals |

---

## 4. End-to-End Event Pipeline

### 4.1 Product publish → search result

```
Step 1 — Admin action
  Admin saves a product in nopCommerce admin panel
  → EntityInsertedEvent<Product> or EntityUpdatedEvent<Product> fires

Step 2 — ProductEventConsumer (inside nopCommerce unit-of-work)
  Checks plugin is Enabled and StoreCode is set
  Determines eventType: published | updated | unpublished | deleted
  
  For publish/update:
    Fetches slug, thumbnail URL, category names concurrently (Task.WhenAll)
    Builds payload with full product metadata
  
  For delete/unpublish:
    Uses fast path — no metadata fetch needed
    Checks HasEventEnqueuedAsync to avoid duplicate rows
  
  Calls OutboxMessage.NewContext() → MessageId, CorrelationId, timestamp
  Calls OutboxService.EnqueueAsync(outboxMessage)
    → SELECT EXISTS check on MessageId
    → INSERT INTO OutboxMessage (same DB transaction)
  Logs: "[Federation.Outbox] Enqueued message {id} for bu-x entity {n} (product.published) to topic 'federation.products'"

Step 3 — OutboxMessage row: ProcessedOnUtc = NULL (pending)

Step 4 — KafkaRelay polls every 5 s
  BEGIN TRANSACTION
  SELECT ... FROM OutboxMessage WHERE ProcessedOnUtc IS NULL AND Attempts < 5
  ORDER BY CreatedOnUtc LIMIT 50 FOR UPDATE SKIP LOCKED
  
  For each row:
    Produce to Kafka:
      Topic:   federation.products
      Key:     bu-a.{messageId}
      Value:   JSON payload
      Headers: X-Store-Code: bu-a
                X-Message-Id: {messageId}
                X-Correlation-Id: {uuid}
    
    If Persisted:
      UPDATE OutboxMessage SET ProcessedOnUtc = NOW()
    Else:
      UPDATE OutboxMessage SET Attempts = Attempts+1, LastError = ...
  
  COMMIT
  Logs: "[Relay:bu-a] Kafka relay batch committed. Published 1, failed 0."

Step 5 — Meilisearch Indexer (consumer group: federation-indexer)
  DrainBatch: collects up to 50 messages within 500 ms
  Parses ProductChangedMessage from JSON
  docId = "bu-a-{productId}"
  
  For product.published / product.updated:
    upserts.Add(ProductDocument)
    index.AddDocumentsAsync(upserts, primaryKey: "id")
    Logs: "[Indexer] Bulk upserted N documents"
  
  consumer.Commit() — advances Kafka offset

Step 6 — Meilisearch products index updated
  { id: "bu-a-42", productName: "Armchair Velvet", productUrl: "http://localhost:5001/armchair-velvet", ... }

Step 7 — Discovery API query
  GET http://localhost:5010/api/search?q=armchair
  → { totalHits: 1, hits: [{ productUrl: "http://localhost:5001/armchair-velvet" }] }

Step 8 — "View ↗" link → http://localhost:5001/armchair-velvet → HTTP 200
```

### 4.2 Product delete → removed from search

```
Step 1 — Admin deletes a product
  EntityUpdatedEvent<Product> {Deleted=true} or EntityDeletedEvent<Product> fires
  Optionally: ActivityLog entry "DeleteProduct" fires ProductDeleteActivityLogConsumer (fallback)

Step 2 — ProductEventConsumer
  eventType = product.deleted
  Fast path — no metadata fetch
  HasEventEnqueuedAsync check — skips if already written
  Writes minimal payload {storeCode, productId, eventType, messageId}
  INSERT INTO OutboxMessage

Step 3 — KafkaRelay picks up the delete row within 5 s
  Produces product.deleted to federation.products
  UPDATE ProcessedOnUtc = NOW()

Step 4 — MeilisearchIndexer
  docId = "bu-a-{productId}"
  deletes.Add(docId)
  index.DeleteDocumentsAsync(deletes)
  WaitForTaskAsync(taskUid, timeout=10s) — confirms deletion
  If task Failed → per-document fallback (DeleteDocumentsOneByOneAsync)
  Logs: "[Indexer] Meilisearch delete task {uid} completed: Succeeded. Removed 1 document(s)."

Step 5 — Discovery API cache expires (1 s TTL)
  Next GET /api/search — document is gone
```

### 4.3 Delivery guarantees summary

| Scenario | Outcome |
|---|---|
| DB transaction rolled back | Outbox row never written → event never sent |
| Kafka publish fails | `ProcessedOnUtc` stays NULL → retried on next 5 s poll |
| Relay crashes mid-batch | Transaction uncommitted → rows remain pending → retried on restart |
| Attempts reaches 5 | Row skipped permanently (dead-letter); visible in Grafana / outbox metrics |
| Duplicate relay (two relay instances) | `FOR UPDATE SKIP LOCKED` prevents concurrent processing of the same row |
| Meilisearch wiped | Watchdog detects 0 docs + processed rows → resets `ProcessedOnUtc` → auto-replay within ~5 s |
| Duplicate Kafka message | Meilisearch `AddDocumentsAsync` is an upsert; delete events are idempotent (deleting a missing doc is a no-op) |
| Indexer crashes during batch | Offset not committed → messages re-consumed from last committed offset |

---

## 5. Data Contracts (`Federation.Contracts`)

**Location:** `FederationPlatform/Federation.Contracts/`

Shared message record used by both the relay (serialisation) and the indexer (deserialisation):

```csharp
record ProductChangedMessage(
    string    MessageId,
    string    CorrelationId,
    string    StoreCode,
    string    StoreName,
    string    EventType,
    int       ProductId,
    string?   ProductName,
    string?   ShortDescription,
    decimal   Price,
    string?   ThumbnailUrl,
    string?   ProductUrl,
    string?   Slug,
    List<string> Categories,
    DateTimeOffset OccurredOnUtc
)
```

For delete/unpublish events the nullable fields are absent; the indexer only uses `StoreCode` + `ProductId` to compute `docId`.

---

## 6. Configuration

### Plugin settings (`FederationOutboxSettings`)

Stored in nopCommerce `Setting` table, seeded per BU by `scripts/data/seed-outbox-settings-bua.sql` / `seed-outbox-settings-bub.sql`:

| Key | BU-A | BU-B |
|---|---|---|
| `StoreCode` | `bu-a` | `bu-b` |
| `StoreName` | `HomeStyle Living` | `WorkForge Industrial` |
| `StorefrontBaseUrl` | `http://localhost:5001` | `http://localhost:5002` |
| `Enabled` | `true` | `true` |

### Keycloak plugin settings

| Key | BU-A | BU-B |
|---|---|---|
| `Authority` | `http://localhost:8080/realms/nop-federation` | same |
| `MetadataAddress` | `http://keycloak:8080/realms/nop-federation/...` | same |
| `ClientId` | `bu-a-client` | `bu-b-client` |

### KafkaRelay environment variables

```
BusinessUnits__bua__ConnectionString
BusinessUnits__bua__StoreCode = bu-a
BusinessUnits__bub__ConnectionString
BusinessUnits__bub__StoreCode = bu-b
Kafka__BootstrapServers = kafka:9092
Meilisearch__Url = http://meilisearch:7700
```

---

## 7. Database Schema (OutboxMessage DDL)

```sql
CREATE TABLE "OutboxMessage" (
    "Id"             serial         PRIMARY KEY,
    "MessageId"      varchar(255)   NOT NULL UNIQUE,
    "StoreCode"      varchar(50)    NOT NULL,
    "StoreName"      varchar(255)   NOT NULL DEFAULT '',
    "EventType"      varchar(100)   NOT NULL,
    "Topic"          varchar(255)   NOT NULL,
    "Payload"        text           NOT NULL,
    "CorrelationId"  varchar(36),
    "EntityId"       integer,
    "CreatedOnUtc"   timestamp      NOT NULL,
    "ProcessedOnUtc" timestamp,
    "LastError"      varchar(2000),
    "Attempts"       integer        NOT NULL DEFAULT 0
);

CREATE INDEX ix_outbox_pending
    ON "OutboxMessage" ("CreatedOnUtc")
    WHERE "ProcessedOnUtc" IS NULL AND "Attempts" < 5;
```

Each BU has its own copy of this table in its isolated PostgreSQL database.

---

## 8. Component Dependency Map

```
nopCommerce BU
  └── ProductEventConsumer
        └── IOutboxService → OutboxMessage (PostgreSQL)
              └── KafkaRelay RelayWorker
                    ├── Kafka ProduceAsync → federation.products
                    └── (watchdog) Meilisearch /indexes/products/stats

Kafka federation.products
  └── IndexerWorker
        ├── Meilisearch AddDocumentsAsync (upsert)
        └── Meilisearch DeleteDocumentsAsync (delete)

Meilisearch products index
  └── Discovery API /api/search, /api/facets
        └── Discovery Web (standalone portal)
        └── Embedded Widget (BU homepages via _FederatedSearch.cshtml)

nopCommerce BU
  └── KeycloakAuthenticationController
        └── OIDC middleware → Keycloak realm nop-federation
              └── IExternalAuthenticationService (nopCommerce customer create/link)

Prometheus
  ├── Blackbox exporter (HTTP probes → all services)
  ├── Postgres exporter BU-A/BU-B (outbox SQL metrics)
  └── Meilisearch /metrics
        └── Grafana dashboards (Business Pulse · Demand Channels · Resilience/SLA)
```

---

## 9. Operations Quick Reference

### Inspect outbox
```bash
./platform.sh outbox [bu-a|bu-b|all] [limit]
./platform.sh outbox-watch all 10 2      # live poll every 2 s
```

### Peek Kafka topic (no offset advance)
```bash
./platform.sh kafka-peek federation.products 10
./platform.sh kafka-peek orders.placed 5
```

### Trace a product end-to-end
```bash
# 1. Outbox row
docker exec nopcommerce_bua_postgres psql -U nopcommerce_bua -d nopcommerce \
  -c 'SELECT "Id","EventType","EntityId","ProcessedOnUtc","Attempts" FROM "OutboxMessage" ORDER BY "CreatedOnUtc" DESC LIMIT 10;'

# 2. Relay log
docker logs federation_kafka_relay --tail 50 | grep "product.deleted"

# 3. Indexer log
docker logs federation_meili_indexer --tail 50 | grep "bu-a-"

# 4. Meilisearch doc count
curl -s http://localhost:7700/indexes/products/stats

# 5. Discovery API
curl -s "http://localhost:5010/api/search?q=*" | python3 -m json.tool
```

### Reset dead-letter rows
```bash
docker exec nopcommerce_bua_postgres psql -U nopcommerce_bua -d nopcommerce \
  -c 'UPDATE "OutboxMessage" SET "Attempts"=0, "LastError"=NULL WHERE "Attempts">=5;'
```

### Force index rebuild (after volume wipe)
```bash
docker compose -f docker-compose.federation.yml restart meilisearch meili-indexer kafka-relay
# Watchdog auto-resets processed rows within 30 s
```

---

## 10. Extension Points

### Adding a new event type
1. Add constant to `FederationOutboxDefaults.EventTypes`.
2. Add message record in `Federation.Contracts/`.
3. Add `IConsumer<EntityXxxEvent<T>>` in the outbox plugin; call `OutboxMessage.NewContext()` + `_outboxService.EnqueueAsync()`.
4. Handle the new event type in `IndexerWorker.ProcessBatchAsync` (or a new worker service consuming a new Kafka topic).

### Adding a third BU
1. Copy `docker-compose.bub.yml` → `docker-compose.buc.yml`; change ports, names, volumes.
2. Add `BUC_DB_PASS` / `BUC_ADMIN_PASS` to `.env`.
3. Add `BusinessUnits__buc__*` env vars in `docker-compose.federation.yml` (relay section).
4. Add `scripts/data/seed-outbox-settings-buc.sql`.
5. The single `federation-indexer` consumer group automatically handles events from the new BU — no indexer changes required.

