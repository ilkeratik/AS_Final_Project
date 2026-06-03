# How It Works — Step-by-Step

> One document, plain language. Trace any action from admin click to search result.  
> For deep-dive diagrams see [`docs/diagrams.md`](diagrams.md).  
> For commands and ports see [`README.md`](../README.md).

---

## The Big Picture in One Sentence

> An admin action inside either BU store writes an event to a local database table.  
> A relay process picks it up, sends it to Kafka, and an indexer updates the shared search index — all automatically, within ~5 seconds.

---

## The Five Layers

```
[ 1. BU Store ]  →  [ 2. Outbox Table ]  →  [ 3. Kafka Relay ]
                                                      ↓
                    [ 5. Search / API ]  ←  [ 4. Meilisearch Indexer ]
```

Each layer is a separate process/container. They communicate only through the database row or the Kafka topic — nothing is shared in memory.

---

## Walk-Through: Admin Publishes a Product

### Step 1 — Admin saves the product in nopCommerce

**What happens:** Admin fills in the product form and clicks Save.  
**Where:** `http://localhost:5001/admin` (BU-A) or `http://localhost:5002/admin` (BU-B)

nopCommerce fires an internal C# event:
```
EntityInsertedEvent<Product>   (new product)
EntityUpdatedEvent<Product>    (edited product)
```

No federation code runs yet — this is standard nopCommerce behaviour.

---

### Step 2 — Plugin captures the event (ProductEventConsumer)

**What happens:** The outbox plugin listens for the event above and writes one database row.  
**Where:** `Plugins/Nop.Plugin.Federation.Outbox/Services/ProductEventConsumer.cs`

What the consumer does, in order:
1. Reads `product.Published` and `product.Deleted` flags to decide the **event type**:
   - Published = true → `product.published`
   - Already existed + still published → `product.updated`
   - Published = false → `product.unpublished`
   - Deleted = true → `product.deleted`
2. For publish/update events only — fetches extra metadata **in parallel**:
   - `UrlRecord` → slug (e.g. `armchair-velvet`)
   - Category names (e.g. `["Furniture", "Living Room"]`)
   - Thumbnail URL
   - Builds the absolute product URL: `http://localhost:5001/armchair-velvet`
3. For delete/unpublish events — **skips** that fetch (the product may already be partially cleaned up in the DB).
4. Calls `OutboxService.EnqueueAsync()` — this inserts one row into `OutboxMessage` **in the same database transaction** as the product save.

> 💡 **Why the same transaction?**  
> If the product save rolls back, the outbox row is also rolled back. There is no way to save a product but lose the event (or save the event without saving the product). This is the Transactional Outbox pattern — see ADR-2 in `README.md`.

**The outbox row looks like:**

| Column | Example value |
|---|---|
| `MessageId` | `bu-a.product.published.42.638500000000` |
| `EventType` | `product.published` |
| `Topic` | `federation.products` |
| `Payload` | `{ "productId":42, "productName":"Armchair Velvet", "slug":"armchair-velvet", … }` |
| `EntityId` | `42` |
| `ProcessedOnUtc` | `NULL` ← pending |
| `Attempts` | `0` |
| `CorrelationId` | `3fa85f64-5717-…` (UUID for tracing) |

**Code file:** `Plugins/Nop.Plugin.Federation.Outbox/Domain/OutboxMessage.cs`  
**Schema SQL:** `scripts/data/init-outbox-schema.sql`

---

### Step 3 — Kafka Relay polls the outbox (every 5 seconds)

**What happens:** A background worker reads pending rows from the database and sends them to Kafka.  
**Where:** `FederationPlatform/Federation.KafkaRelay/Workers/RelayWorker.cs`  
**One `RelayWorker` per BU** — configured via `BusinessUnits__bua__*` env vars.

**The polling query (every 5 s):**
```sql
SELECT Id, MessageId, Topic, EventType, EntityId, Payload, CorrelationId, Attempts
FROM   "OutboxMessage"
WHERE  ProcessedOnUtc IS NULL AND Attempts < 5
ORDER  BY CreatedOnUtc
LIMIT  50
FOR UPDATE SKIP LOCKED
```

Key points:
- `FOR UPDATE SKIP LOCKED` — if two relay instances run at the same time, they won't process the same row twice.
- `Attempts < 5` — rows that failed 5 times are **dead-lettered** (skipped forever until manually reset).
- Batch size: **≤ 50 rows** per cycle to keep latency predictable.

**For each row the relay:**
1. Calls Kafka `ProduceAsync(topic, key, payload, headers)`:
   - `key` = `{storeCode}.{messageId}`
   - Headers include `X-Store-Code`, `X-Message-Id`, `X-Correlation-Id`
   - Producer config: `Acks=All`, `EnableIdempotence=true` (at-least-once, no silent data loss)
2. If Kafka confirms → `UPDATE OutboxMessage SET ProcessedOnUtc = NOW()`
3. If Kafka fails → `UPDATE OutboxMessage SET Attempts += 1, LastError = '...'`

After the batch: logs `"Kafka relay batch committed. Published N, failed M."`

> 💡 **What is "at-least-once"?**  
> If the relay crashes after Kafka accepts the message but before it writes `ProcessedOnUtc`, the row stays pending and is re-sent on the next poll. The same event may reach Kafka twice — which is why consumers must be **idempotent** (safe to process the same message more than once).

**Idempotency key:** `MessageId` is deterministic — same product + same event type + same ticks = same ID. The indexer uses it to deduplicate.

---

### Step 4 — Meilisearch Indexer consumes from Kafka

**What happens:** A Kafka consumer reads messages from `federation.products` and upserts/deletes documents in Meilisearch.  
**Where:** `FederationPlatform/Federation.MeilisearchIndexer/Workers/IndexerWorker.cs`  
**Consumer group:** `federation-indexer` (Kafka tracks the offset; restarts pick up where they left off)

**Batch strategy — DrainBatch():**
Instead of processing one message at a time, the indexer:
1. Reads messages for up to **500 ms** or **50 messages**, whichever comes first.
2. Splits into two lists: upserts and deletes.
3. Makes **one** bulk Meilisearch API call for each list.

This reduces HTTP round-trips from N (one per product) to ≤ 2 per 500 ms window.

**Event routing:**

| EventType | Meilisearch action |
|---|---|
| `product.published` | `AddDocumentsAsync` (upsert — insert or replace) |
| `product.updated` | `AddDocumentsAsync` (upsert) |
| `product.deleted` | `DeleteDocumentsAsync` |
| `product.unpublished` | `DeleteDocumentsAsync` |

**The Meilisearch document:**
```json
{
  "id": "bu-a-42",
  "productId": 42,
  "storeCode": "bu-a",
  "storeName": "HomeStyle Living",
  "productName": "Armchair Velvet",
  "productUrl": "http://localhost:5001/armchair-velvet",
  "categories": ["Furniture", "Living Room"],
  "price": 349.00,
  "publishedAt": "2026-06-03T10:00:00Z"
}
```

**Document ID formula:** `{storeCode}-{productId}` (e.g. `bu-a-42`)  
- Globally unique across all BUs.  
- BU-A and BU-B can both have product #42 without collision.  
- Deleting `bu-a-42` never touches `bu-b-42`.

After a delete the indexer waits for Meilisearch to confirm the task succeeded (async task polling with `WaitForTaskAsync`). If the bulk delete fails, it falls back to deleting documents one by one.

---

### Step 5 — Discovery API and Web serve the result

**What happens:** Shoppers (or the embedded widget) query a single HTTP endpoint and get products from both BUs in one response.  
**Where:** `FederationPlatform/Federation.Discovery.Api/Program.cs` — port `5010`

```
GET http://localhost:5010/api/search?q=armchair
→ { "totalHits": 3, "hits": [{ "id":"bu-a-42", "productUrl":"http://localhost:5001/armchair-velvet", … }] }
```

The API wraps Meilisearch queries with a short cache (1 s for search results, 5 s for facets) so a deleted product disappears from results within ~1 second after the indexer task completes.

**Discovery Web** (`port 5011`) is the standalone cross-BU search portal — same API, rendered as a full UI with store-filter chips.

**Embedded widget** — `FederationPlatform/Federation.DiscoveryClient/federated-search.js` — is included on each BU's homepage via `Presentation/Nop.Web/Views/Home/_FederatedSearch.cshtml`.

---

## Walk-Through: Admin Deletes a Product

Same pipeline — one difference: the consumer uses a **fast path** that skips the metadata fetch.

```
1.  Admin clicks Delete in nopCommerce admin
2.  EntityUpdatedEvent<Product> { Deleted = true }
3.  ProductEventConsumer → EventType = "product.deleted"
    └── Skips slug / category / thumbnail fetch
    └── INSERT OutboxMessage { Payload: { storeCode, productId } }
4.  KafkaRelay polls → produces to Kafka → marks ProcessedOnUtc
5.  MeilisearchIndexer → DeleteDocumentsAsync(["bu-a-42"])
    └── WaitForTaskAsync → confirms deletion
6.  Next search → bu-a-42 is gone ✅
```

**Fallback — ActivityLog consumer:**  
If the direct product event is missed for any reason (e.g. cascade cleanup happens before the event fires), a second consumer catches the admin activity log:

| File | What it does |
|---|---|
| `Services/ProductDeleteActivityLogConsumer.cs` | Listens for `EntityInsertedEvent<ActivityLog>` where `SystemKeyword == "DeleteProduct"`, then enqueues a `product.deleted` outbox row |
| `Services/OutboxService.cs` (`HasEventEnqueuedAsync`) | Checks for an existing row so the two paths don't write duplicate delete events |

---

## Walk-Through: SSO Login

```
1.  User clicks "Login with SSO" on BU-A or BU-B storefront
2.  Browser is redirected to Keycloak :8080
    → URL: /realms/nop-federation/protocol/openid-connect/auth?client_id=bu-a-client&…
3.  User enters credentials once in Keycloak
4.  Keycloak redirects back to /keycloakauthentication/callback
    → OIDC middleware validates state cookie, exchanges auth code for id_token + access_token
5.  Middleware redirects to /keycloakauthentication/login-callback
    → KeycloakAuthenticationController.LoginCallbackAsync()
    → Maps given_name/family_name → FirstName/LastName on the nopCommerce Customer record
    → Calls IExternalAuthenticationService.AuthenticateAsync()
6.  nopCommerce session established — same Keycloak account works on BU-B too
```

**Why two routes?** A single callback route causes a session-state loss bug (OIDC middleware consumes the state cookie before the app-level handler runs). The two-route design in `Infrastructure/RouteProvider.cs` fixes this.

**Plugin files:**  
`Plugins/Nop.Plugin.ExternalAuth.Keycloak/` — `KeycloakAuthenticationRegistrar.cs`, `KeycloakAuthenticationController.cs`, `RouteProvider.cs`

---

## The Outbox Dead-Letter and Retry Rules

| State | Condition | What happens |
|---|---|---|
| **Pending** | `ProcessedOnUtc IS NULL AND Attempts < 5` | Relay picks it up on next poll |
| **Processed** | `ProcessedOnUtc IS NOT NULL` | Relay skips it; indexer has seen it |
| **Dead-letter** | `Attempts >= 5` | Relay skips it permanently |
| **Retry a dead-letter** | Manual: `UPDATE … SET Attempts=0, LastError=NULL` | Goes back to Pending |

Constant: `FederationOutboxDefaults.MaxAttempts = 5`  
File: `Plugins/Nop.Plugin.Federation.Outbox/FederationOutboxDefaults.cs`

---

## The Watchdog (Auto-Recovery)

**Where:** `FederationPlatform/Federation.KafkaRelay/Workers/RelayWorker.cs` — runs every 5 minutes.

**What it does:**
1. Calls `GET http://meilisearch:7700/indexes/products/stats`
2. If `numberOfDocuments == 0` **and** processed product outbox rows exist → resets those rows (`ProcessedOnUtc = NULL`) for replay.
3. On the next relay poll cycle, all products are re-published to Kafka → indexer rebuilds the index.
4. If the outbox table is empty (fresh install) → skips, logs a message.

This means: if Meilisearch's volume is wiped, the full product index self-heals within ~30 seconds, with no manual intervention.

---

## Startup Bootstrap (OutboxSeedHostedService)

**Where:** `Plugins/Nop.Plugin.Federation.Outbox/Services/OutboxSeedStartupTask.cs`

On every nopCommerce start:
1. Waits 5 seconds for the app to fully boot.
2. Loads `FederationOutboxSettings` (storeCode, storeName, enabled flag).
3. Checks if `OutboxMessage` table is empty:
   - **Empty (fresh install)** → skips. Products will flow in naturally as they are created.
   - **Has rows** → finds any published products with no corresponding outbox row and seeds them.

This ensures a restart after a partial failure catches up any missed events automatically.

---

## Observability: What Gets Measured

### Prometheus metrics (auto-scraped)

| Metric | Source | Meaning |
|---|---|---|
| `federation_outbox_pending{bu}` | Postgres exporter → `OutboxMessage` table | How many events are waiting to be relayed |
| `federation_outbox_deadletter{bu}` | Same | Events stuck at Attempts ≥ 5 |
| `federation_outbox_oldest_pending_age_seconds{bu}` | Same | How old the oldest un-relayed row is |
| `meilisearch_index_docs_count{index}` | Meilisearch `/metrics` | Total documents in the search index |
| `meilisearch_http_requests_total{path,status}` | Same | Search request volume and errors |
| `probe_success{instance}` | Blackbox exporter | HTTP health of each service |

### Grafana dashboards (`http://localhost:3000`, admin/admin)

| Dashboard | What to look for |
|---|---|
| **Federation Business Pulse** | Product lifecycle counts (published/updated/deleted), order and customer event volumes |
| **Federation Demand Channels** | Search request rate and latency on the Discovery API |
| **Federation Resilience and SLA** | Outbox backlog draining to 0, endpoint availability, dead-letter count |

Dashboard JSON files: `monitoring/grafana/dashboards/business/`  
Metric SQL queries: `monitoring/postgres-exporter/queries.yaml`

---

## Where to Find What

| Feature | Key file(s) |
|---|---|
| Outbox row written | `Plugins/Nop.Plugin.Federation.Outbox/Services/ProductEventConsumer.cs` |
| Outbox schema | `Plugins/Nop.Plugin.Federation.Outbox/Domain/OutboxMessage.cs`, `scripts/data/init-outbox-schema.sql` |
| Idempotency / enqueue logic | `Plugins/Nop.Plugin.Federation.Outbox/Services/OutboxService.cs` |
| Startup catch-up | `Plugins/Nop.Plugin.Federation.Outbox/Services/OutboxSeedStartupTask.cs` |
| Delete fallback (activity log) | `Plugins/Nop.Plugin.Federation.Outbox/Services/ProductDeleteActivityLogConsumer.cs` |
| Plugin constants (topics, MaxAttempts) | `Plugins/Nop.Plugin.Federation.Outbox/FederationOutboxDefaults.cs` |
| Plugin settings (storeCode, storeName) | `Plugins/Nop.Plugin.Federation.Outbox/FederationOutboxSettings.cs` |
| DI registrations | `Plugins/Nop.Plugin.Federation.Outbox/Infrastructure/DependencyRegistrar.cs` |
| Kafka relay loop + watchdog | `FederationPlatform/Federation.KafkaRelay/Workers/RelayWorker.cs` |
| Relay startup (one worker per BU) | `FederationPlatform/Federation.KafkaRelay/Program.cs` |
| Meilisearch indexer (batch drain + routing) | `FederationPlatform/Federation.MeilisearchIndexer/Workers/IndexerWorker.cs` |
| Message contracts (payload shape) | `FederationPlatform/Federation.Contracts/` |
| Discovery API (/api/search, /api/facets) | `FederationPlatform/Federation.Discovery.Api/Program.cs` |
| Cross-BU search web portal | `FederationPlatform/Federation.Discovery.Web/` |
| Embedded search widget (JS) | `FederationPlatform/Federation.DiscoveryClient/federated-search.js` |
| Widget partial view | `Presentation/Nop.Web/Views/Home/_FederatedSearch.cshtml` |
| SSO plugin (OIDC middleware) | `Plugins/Nop.Plugin.ExternalAuth.Keycloak/Infrastructure/KeycloakAuthenticationRegistrar.cs` |
| SSO controller (login callback) | `Plugins/Nop.Plugin.ExternalAuth.Keycloak/Controllers/KeycloakAuthenticationController.cs` |
| SSO two-route fix | `Plugins/Nop.Plugin.ExternalAuth.Keycloak/Infrastructure/RouteProvider.cs` |
| Keycloak realm config | `FederationPlatform/keycloak-realm.json` |
| Outbox metric SQL | `monitoring/postgres-exporter/queries.yaml` |
| Grafana dashboard JSON | `monitoring/grafana/dashboards/business/` |
| All Mermaid diagrams | `docs/diagrams.md` |
| Full ops commands | `README.md` → Operations section |
| Architecture decisions (ADRs) | `README.md` → Architecture Design Decisions |

---

## Quick Diagnostic Checklist

When something doesn't appear in search:

```
1. Was the outbox row written?
   ./platform.sh outbox bu-a 10

2. Did the relay send it to Kafka?
   docker logs federation_kafka_relay --tail 50 | grep "product."

3. Did the indexer receive it?
   docker logs federation_meili_indexer --tail 50 | grep "bu-a-"

4. Is it in Meilisearch?
   curl http://localhost:7700/indexes/products/stats

5. Does the API return it?
   curl "http://localhost:5010/api/search?q=<name>"
```

When a deleted product still appears:
```
# Check if the delete row exists and was processed
./platform.sh outbox bu-a 20
# Then grep relay + indexer logs for "product.deleted"
docker logs federation_kafka_relay --tail 100 | grep "product.deleted"
docker logs federation_meili_indexer --tail 100 | grep "deleted"
```

---

*Last updated: 2026-06-03*

