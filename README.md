# nopCommerce Federated Commerce Platform

A **two-BU federated commerce system** built on nopCommerce — two fully isolated stores sharing a common event backbone, unified search index, and SSO identity provider.

## Repository summary
- **/docs:** Design and implementation documents, slides and diagrams
- **/source_code:** Nopcommerce and developed features including containers and scripts

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Technology Stack](#technology-stack)
3. [Services & Ports](#services--ports)
4. [Quick Start](#quick-start)
5. [Architecture Design Decisions](#architecture-design-decisions)
6. [Federation Data Flow](#federation-data-flow)
7. [Components In Detail](#components-in-detail)
8. [Observability & Dashboards](#observability--dashboards)
9. [Operations](#operations)
10. [Development Guide](#development-guide)
11. [File Structure](#file-structure)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          federation-net (Docker network)                        │
│                                                                                 │
│  ┌────────────────────────────┐    ┌────────────────────────────┐               │
│  │  BU-A  :5001               │    │  BU-B  :5002               │               │
│  │  HomeStyle Living          │    │  WorkForge Industrial       │               │
│  │  ─────────────────         │    │  ─────────────────          │               │
│  │  nopCommerce Web           │    │  nopCommerce Web            │               │
│  │  + Federation.Outbox       │    │  + Federation.Outbox        │               │
│  │  + ExternalAuth.Keycloak   │    │  + ExternalAuth.Keycloak    │               │
│  │            │               │    │            │                │               │
│  │  PostgreSQL :5433          │    │  PostgreSQL :5434           │               │
│  │  (OutboxMessage table)     │    │  (OutboxMessage table)      │               │
│  └────────────┬───────────────┘    └────────────┬───────────────┘               │
│               │   poll every 5 s (SKIP LOCKED)  │                               │
│               └────────────────┬────────────────┘                               │
│                                ▼                                                 │
│                  ┌─────────────────────────┐                                    │
│                  │  Kafka Relay            │  at-least-once, idempotent         │
│                  │  (one RelayWorker/BU)   │  X-Correlation-Id tracing          │
│                  └─────────────┬───────────┘                                    │
│                                ▼                                                 │
│                  ┌─────────────────────────┐                                    │
│                  │  Kafka :9092 (KRaft)    │  federation.products               │
│                  │                         │  orders.placed                     │
│                  └─────────────┬───────────┘  customers.created                 │
│                                ▼                                                 │
│                  ┌─────────────────────────┐                                    │
│                  │  Meilisearch Indexer    │  batch ≤50 msgs / 500 ms           │
│                  │  published  → upsert   │  id = {storeCode}-{productId}      │
│                  │  deleted    → delete   │                                     │
│                  └─────────────┬───────────┘                                    │
│                                ▼                                                 │
│                  ┌─────────────────────────┐   ┌──────────────────────────────┐│
│                  │  Meilisearch :7700      │──►│  Discovery API  :5010        ││
│                  │  products index         │   │  GET /api/search             ││
│                  └─────────────────────────┘   │  GET /api/facets             ││
│                                                 └──────────────┬───────────────┘│
│                                                                ▼                │
│                                                 ┌──────────────────────────────┐│
│                                                 │  Discovery Web  :5011        ││
│                                                 │  Cross-BU search UI          ││
│                                                 └──────────────────────────────┘│
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  Keycloak :8080   realm: nop-federation                                 │   │
│  │  bu-a-client ←→ BU-A          bu-b-client ←→ BU-B                      │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  Observability  Prometheus :9090  ·  Grafana :3000  ·  14 dashboards    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

**Key properties:**
- Each BU has its own PostgreSQL + nopCommerce container — **complete failure isolation**
- Events flow via a **transactional outbox** — no dual-write anomaly, at-least-once delivery
- Product **publish, update, and delete** all flow through the same pipeline automatically
- Meilisearch holds a **unified cross-BU product index** exposed by the Discovery API
- Keycloak provides **SSO** — one account works on both stores

> 📊 **Full Mermaid diagrams** (C4 context, state machine, sequence flows, observability stack) are in [`docs/diagrams.md`](docs/diagrams.md).  
> 📖 **Plain-language step-by-step walkthrough** (one action → outbox → relay → Kafka → indexer → search) is in [`docs/how_it_works.md`](docs/how_it_works.md).

---

## Technology Stack

| Layer | Technology | Version | Purpose |
|---|---|---|---|
| Store platform | nopCommerce | 4.7 (ASP.NET Core 9) | B2C commerce engine |
| Database | PostgreSQL | 15 (per-BU) | Isolated transactional store |
| Event transport | Apache Kafka | 3.7 (KRaft, no Zookeeper) | Durable ordered message log |
| Search engine | Meilisearch | v1.8 | Full-text + faceted cross-BU index |
| Identity | Keycloak | 25 | OIDC/OAuth2 SSO |
| Container runtime | Docker + Compose | v2 | Local orchestration |
| Languages | C# 13 / .NET 9 | — | Plugin + worker services |
| Observability | Prometheus + Grafana | latest | Real-time metrics, 8 dashboards |

---

## Services & Ports

| Service | Port | URL | Health check |
|---|---|---|---|
| BU-A storefront | 5001 | http://localhost:5001 | `/favicon.ico` → 200 |
| BU-B storefront | 5002 | http://localhost:5002 | `/favicon.ico` → 200 |
| BU-A PostgreSQL | 5433 | `psql -p 5433` | `pg_isready` |
| BU-B PostgreSQL | 5434 | `psql -p 5434` | `pg_isready` |
| Keycloak | 8080 | http://localhost:8080 | `/health/ready` |
| Kafka broker | 9092 | `kafka:9092` (internal) | broker-api-versions |
| Meilisearch | 7700 | http://localhost:7700 | `/health` → 200 |
| Discovery API | 5010 | http://localhost:5010/api/search | `/health` → 200 |
| Discovery Web | 5011 | http://localhost:5011 | `/health` → 200 |
| Prometheus | 9090 | http://localhost:9090 | `/` → 302 |
| Grafana | 3000 | http://localhost:3000 | `/` → 200 (admin/admin) |
| Blackbox exporter | 9115 | http://localhost:9115 | HTTP probes |
| Postgres exporter BU-A | 9187 | http://localhost:9187/metrics | outbox metrics |
| Postgres exporter BU-B | 9188 | http://localhost:9188/metrics | outbox metrics |

**Admin credentials (default `.env` values):**

| BU | Admin URL | Email | Password |
|---|---|---|---|
| BU-A | http://localhost:5001/admin | admin@bu-a.example.com | BuA@Admin123! |
| BU-B | http://localhost:5002/admin | admin@bu-b.example.com | BuB@Admin123! |
| Keycloak | http://localhost:8080 | admin | admin |

---

## Quick Start

### Prerequisites
- Docker Desktop (or Docker Engine + Compose v2)
- 8 GB RAM recommended
- macOS / Linux / WSL2

### 1 · Configure credentials
```bash
cp .env.example .env
# Edit .env — set BUA_DB_PASS, BUA_ADMIN_PASS, BUB_DB_PASS, BUB_ADMIN_PASS
```

### 2 · Start everything
```bash
./platform.sh start
```

This single command:
- Creates `federation-net` Docker network
- Starts BU-A and BU-B stacks (PostgreSQL + nopCommerce)
- Starts all federation services (Keycloak, Kafka, Meilisearch, relay, indexer, Discovery API/Web)
- Starts the monitoring stack (Prometheus, Grafana, exporters)
- Seeds Keycloak OIDC settings into each BU

### 3 · Product index seeding
No manual replay is required. On first boot each BU's `OutboxSeedHostedService` checks whether there are
unrelayed products and enqueues them automatically. On a truly fresh install the outbox table is empty so
the service skips bootstrapping entirely — products flow into the index organically as they are created.

### 4 · Verify
```bash
./platform.sh status
curl -s "http://localhost:5010/api/search?q=*" | python3 -m json.tool
# totalHits should match the published product count across both BUs
```

### Useful variants
```bash
./platform.sh status                     # show all container health
./platform.sh stop                       # stop everything
./platform.sh start --federation-only    # federation services only (skip BU rebuild)
./platform.sh start --no-monitoring      # federation + BUs only
```

---

## Architecture Design Decisions

### ADR-1 — Isolated BU Deployments

**Problem:** Multiple brands must fail independently.

**Decision:** Each BU is a separate Docker Compose project (`nop-bua` / `nop-bub`) with its own PostgreSQL container, named external volume, and nopCommerce process. The two stacks share only the `federation-net` overlay network.

**Result:** `docker compose -f docker-compose.bua.yml down` has zero impact on BU-B, its database, or the shared discovery index.

---

### ADR-2 — Transactional Outbox (at-least-once delivery)

**Problem:** Publishing directly to Kafka inside a nopCommerce event handler risks a dual-write — the DB may commit while the Kafka publish fails (or vice versa), silently dropping events.

**Decision:** [Transactional Outbox pattern](https://microservices.io/patterns/data/transactional-outbox.html). The plugin writes the event into `OutboxMessage` **in the same PostgreSQL transaction** as the domain change. A separate `KafkaRelay` process polls and publishes independently.

```
Domain change (nopCommerce)
  └─► OutboxMessage INSERT  ← same DB transaction
            │
            │  KafkaRelay polls every 5 s
            │  SELECT … FOR UPDATE SKIP LOCKED (batch ≤ 50)
            ▼
         Kafka topic  (Acks=All, EnableIdempotence=true)
            │
            ▼
     Downstream consumer  (indexer, CRM, ERP …)
```

**Delivery guarantees:**
| Scenario | Outcome |
|---|---|
| DB rollback | Outbox row never written → Kafka never sees it |
| Kafka publish fails | `ProcessedOnUtc` stays NULL → retried next poll |
| Attempts ≥ 5 | Row skipped permanently (dead-letter) |
| Duplicate relay | `MessageId` is deterministic → idempotent consumers deduplicate |
| Meilisearch wiped | Relay watchdog detects empty index → resets product rows for replay |

---

### ADR-3 — Centralized Meilisearch Discovery

**Problem:** nopCommerce's built-in Lucene search is per-instance; cross-BU product search requires a shared index.

**Decision:** `MeilisearchIndexer` consumes `federation.products` from Kafka and maintains a single `products` index. `Discovery API` exposes it over HTTP. `Discovery Web` provides a standalone cross-brand UI.

**Document ID:** `{storeCode}-{productId}` — globally unique across all BUs, enabling:
- Independent per-BU upserts and deletes
- Faceted filtering by `storeCode`
- Zero risk of cross-BU document collisions

---

## Federation Data Flow

### Product publish → search result (happy path)

```
1. Admin saves/edits a product in nopCommerce (BU-A or BU-B)
   EntityInsertedEvent<Product> / EntityUpdatedEvent<Product> fired
   │
2. ProductEventConsumer (Nop.Plugin.Federation.Outbox)
   ├── Logs "Product N captured as product.published"
   ├── Fetches slug from UrlRecord      →  "armchair-velvet"
   ├── Fetches categories (parallel)    →  ["Furniture", "Living Room"]
   ├── Fetches thumbnail URL
   ├── Builds absolute productUrl       →  "http://localhost:5001/armchair-velvet"
   └── MessageId = {storeCode}.product.published.{id}.{ticks}  (deterministic)
   │
   INSERT INTO OutboxMessage (same DB transaction)
   Logs "Enqueued message … to topic federation.products"
   │
3. OutboxMessage — ProcessedOnUtc IS NULL (pending)
   │
   KafkaRelay polls every 5 s (SELECT … FOR UPDATE SKIP LOCKED, batch ≤ 50)
   Logs "Processing N outbox message(s) for Kafka"
   Logs per-row "Publishing row N (product.published) for entity M to topic …"
   │
4. Kafka  federation.products
   Key: {storeCode}.{messageId}
   Headers: X-Store-Code, X-Message-Id, X-Correlation-Id
   Acks=All, Idempotence=true
   │
   UPDATE OutboxMessage SET ProcessedOnUtc = NOW()
   Logs "Kafka relay batch committed. Published N, failed 0."
   │
5. MeilisearchIndexer (consumer group: federation-indexer)
   ├── Drains ≤ 50 messages per 500 ms window
   ├── Logs "Kafka message {id} (product.published) for bu-a-42"
   └── product.published/updated → AddDocumentsAsync
   Logs "Bulk upserted N documents"
   │
6. Meilisearch products index
   { id:"bu-a-42", productName:"Armchair Velvet", productUrl:"…/armchair-velvet", … }
   │
7. GET http://localhost:5010/api/search?q=armchair
   → { totalHits:1, hits:[{ productUrl:"http://localhost:5001/armchair-velvet" }] }
   │
8. "View ↗" link → http://localhost:5001/armchair-velvet  ← HTTP 200 ✅
```

### Product delete / unpublish → removed from search

```
1. Admin deletes or unpublishes a product
   EntityUpdatedEvent<Product> {Deleted=true or Published=false} fired
   │
2. ProductEventConsumer
   ├── Logs "Product N captured as product.deleted (published=false, deleted=true)"
   └── EventType = product.deleted (or product.unpublished)
   │
   INSERT INTO OutboxMessage  (same tx)
   │
3. KafkaRelay picks up the delete row on next poll
   Logs "Publishing row N (product.deleted) for entity M …"
   Produces to Kafka → UPDATE ProcessedOnUtc = NOW()
   │
4. MeilisearchIndexer
   ├── Logs "Kafka message (product.deleted) for bu-a-42"
   ├── Logs "Deleting 1 document(s) from Meilisearch"
   └── DeleteDocumentsAsync(["bu-a-42"])
   Logs "Bulk deleted 1 documents"
   │
5. Next search — bu-a-42 is gone from results ✅
```

### SSO login (Keycloak OIDC)

```
Browser → BU storefront → "Login with SSO"
  │  302 redirect to Keycloak /authorize?client_id=bu-{a|b}-client&state=…
  ▼
Keycloak :8080 — validates credentials, issues id_token + access_token
  │  302 redirect to /keycloakauthentication/callback
  ▼
OIDC middleware — code exchange → id_token (given_name, family_name, email, sub)
  │  302 redirect to /keycloakauthentication/login-callback
  ▼
KeycloakAuthenticationController
  ├── Maps given_name / family_name → FirstName / LastName
  └── IExternalAuthenticationService.AuthenticateAsync()
  ▼
nopCommerce customer session established
  └── Same Keycloak account works on both BU-A and BU-B (true SSO) ✅
```

---

## Components In Detail

### BU Stores

Standard nopCommerce 4.7 with two federation plugins baked into the Docker image (`Presentation/Nop.Web/Dockerfile`):

| Plugin | Purpose |
|---|---|
| `Nop.Plugin.Federation.Outbox` | Writes product / order / customer events to `OutboxMessage` table; exposes `OutboxSeedHostedService` for catch-up on restart |
| `Nop.Plugin.ExternalAuth.Keycloak` | OIDC SSO login button + callback handler; two-route design prevents session state loss |

Product catalogs:

| BU | Store Name | Product Focus |
|---|---|---|
| BU-A | HomeStyle Living | Furniture, kitchen, bedding, lighting, garden, smart home, storage |
| BU-B | WorkForge Industrial | Power tools, safety, lifting, welding, electrical, fasteners, workwear |

---

### Federation Outbox Plugin

**Location:** `Plugins/Nop.Plugin.Federation.Outbox/`

Three `IConsumer<T>` handlers fire inside nopCommerce's unit of work:

| Consumer | Handles | Event types emitted | Topic |
|---|---|---|---|
| `ProductEventConsumer` | Insert / Update / Delete `Product` | `product.published`, `product.updated`, `product.deleted`, `product.unpublished` | `federation.products` |
| `OrderEventConsumer` | Insert / Update `Order` | `order.placed`, `order.updated`, `order.cancelled` | `orders.placed` |
| `CustomerEventConsumer` | Insert / Update `Customer` | `customer.created`, `customer.updated` | `customers.created` |

All consumers are idempotent — `MessageId` is deterministic so replays are safe.

**`OutboxService`** logs every enqueue (including duplicate skips) so the pipeline is fully observable.

**`OutboxSeedHostedService`** on startup:
1. Loads `FederationOutboxSettings` (waits 5 s for nopCommerce boot)
2. If outbox table is empty → **fresh install** — skips population entirely
3. Otherwise → checks for published products that have no outbox row and seeds them

`OutboxMessage` schema:

| Column | Type | Notes |
|---|---|---|
| `MessageId` | varchar UNIQUE | Idempotency key — `{storeCode}.{eventType}.{entityId}.{utcTicks}` |
| `EventType` | varchar | `product.published` / `updated` / `deleted` / `unpublished` |
| `Topic` | varchar | Kafka topic name |
| `Payload` | text | JSON — matches `ProductChangedMessage` / `OrderPlacedMessage` / `CustomerCreatedMessage` |
| `EntityId` | int | `Product.Id` / `Order.Id` / `Customer.Id` |
| `ProcessedOnUtc` | datetime? | NULL = pending; set by relay on Kafka confirmation |
| `Attempts` | int | Incremented on failure; rows with Attempts ≥ 5 skipped (dead-letter) |
| `LastError` | varchar(2000) | Last failure message |
| `CorrelationId` | varchar(36) | UUID propagated via Kafka headers for distributed tracing |

Key constants in `FederationOutboxDefaults`:
- `MaxAttempts = 5` — shared between `OutboxService` and `RelayWorker`
- Topics: `federation.products`, `orders.placed`, `customers.created`

---

### Kafka Relay

**Location:** `FederationPlatform/Federation.KafkaRelay/`

One `RelayWorker` per BU. Runs the reliability loop every 5 s with exponential backoff (cap 60 s):

```
BEGIN TRANSACTION
SELECT Id, MessageId, Topic, EventType, EntityId, Payload, CorrelationId, Attempts
FROM   OutboxMessage
WHERE  ProcessedOnUtc IS NULL AND Attempts < 5
ORDER  BY CreatedOnUtc
LIMIT  50
FOR UPDATE SKIP LOCKED

for each row:
  log "Publishing row {Id} ({EventType}) for entity {EntityId} to topic {Topic}"
  ProduceAsync(topic, key={storeCode}.{messageId}, value=payload,
               headers: X-Store-Code, X-Message-Id, X-Correlation-Id)

  if PersistenceStatus.Persisted  → UPDATE ProcessedOnUtc = NOW()
                                    log "Kafka persisted row {Id} ({EventType})"
  else                            → UPDATE Attempts += 1, LastError = status
                                    log warning with EventType + EntityId

COMMIT
log "Kafka relay batch committed. Published {N}, failed {M}."
```

**Watchdog** (runs every 5 min after 30 s initial delay):
- Checks Meilisearch `/indexes/products/stats`
- If `numberOfDocuments == 0` and processed product rows exist → resets them for replay
- If table is empty (fresh install) → logs and skips

Producer config: `Acks=All`, `EnableIdempotence=true`, `MessageSendMaxRetries=5`.

---

### Meilisearch Indexer

**Location:** `FederationPlatform/Federation.MeilisearchIndexer/`  
**Consumer group:** `federation-indexer`

On startup: calls `admin.CreateTopicsAsync()` to ensure `federation.products` exists before subscribing — handles Kafka startup race condition.

Batch strategy: `DrainBatch()` collects ≤ 50 messages within a 500 ms window before issuing one bulk Meilisearch call — reduces HTTP round-trips from N to ≤ 2 per window.

**Event routing:**
| Event type | Action |
|---|---|
| `product.published` | `AddDocumentsAsync` (upsert) |
| `product.updated` | `AddDocumentsAsync` (upsert) |
| `product.deleted` | `DeleteDocumentsAsync` |
| `product.unpublished` | `DeleteDocumentsAsync` |

Index configuration:
- **Searchable:** `productName`, `shortDescription`, `categories`, `storeName`, `slug`
- **Filterable:** `storeCode`, `categories`, `price`
- **Sortable:** `price`, `publishedAt`
- **Document ID:** `{storeCode}-{productId}` (globally unique across all BUs)

---

### Discovery API

**Location:** `FederationPlatform/Federation.Discovery.Api/` — port 5010

| Endpoint | Query params | Cache TTL | Notes |
|---|---|---|---|
| `GET /api/search` | `q`, `stores` (comma-sep), `page`, `pageSize` (1–100), `sort` (`price:asc/desc`, `date:desc`) | 5 s | Full-text + faceted search |
| `GET /api/facets` | — | 30 s | Per-BU hit counts + store names |
| `GET /health` | — | — | Liveness check |

Example responses:
```json
GET /api/search?q=armchair&stores=bu-a
{
  "query": "armchair", "totalHits": 3, "page": 0, "pageSize": 20,
  "hits": [{ "id": "bu-a-4", "storeName": "HomeStyle Living",
             "productUrl": "http://localhost:5001/armchair-velvet", … }]
}

GET /api/facets
{
  "stores": {
    "bu-a": { "count": 33, "name": "HomeStyle Living" },
    "bu-b": { "count": 32, "name": "WorkForge Industrial" }
  }
}
```

---

### Discovery Web & Embedded Widget

**Standalone portal** — `FederationPlatform/Federation.Discovery.Web/` port 5011  
Neutral cross-brand UI: debounced search, store-filter chips (populated from `/api/facets`), price sorting, slug-based "View ↗" deep links.

**Embedded widget** — `FederationPlatform/Federation.DiscoveryClient/federated-search.js`  
Vanilla ES6 module embedded on each BU's homepage via `Views/Home/_FederatedSearch.cshtml`. Auto-applies brand theme (BU-A blue / BU-B green). Reads `data-api-base` from the partial view (set via `FederatedSearch:ApiBase` config, defaults to `http://localhost:5010`).

`productUrl` is always an absolute slug URL — no numeric `/product/{id}` fallback.

---

### Keycloak SSO

**Container:** `federation_keycloak` — port 8080  
**Realm:** `nop-federation` — auto-imported from `FederationPlatform/keycloak-realm.json`

`Nop.Plugin.ExternalAuth.Keycloak` registers OIDC middleware via `KeycloakAuthenticationRegistrar`. Two routes prevent session-state loss:
- `/keycloakauthentication/callback` — OIDC middleware endpoint (state cookie preserved here)
- `/keycloakauthentication/login-callback` — app-level route that completes sign-in

`KeycloakAuthenticationEventConsumer` maps `given_name` / `family_name` claims → `FirstName` / `LastName` on the nopCommerce customer record.

Per-BU settings seeded by `platform.sh`:

| Setting key | BU-A | BU-B |
|---|---|---|
| `Authority` | `http://localhost:8080/realms/nop-federation` | same |
| `MetadataAddress` | `http://keycloak:8080/realms/nop-federation/…` | same |
| `ClientId` | `bu-a-client` | `bu-b-client` |

All defaults centralised in `KeycloakAuthenticationDefaults.cs`.

---

## Observability & Dashboards

The monitoring stack (`monitoring/docker-compose.prometheus.yml`, started automatically by `platform.sh`) provides **real, presentation-ready metrics** — no application code changes required.

### Metric sources

| Exporter | Scrapes | Metrics produced |
|---|---|---|
| Blackbox exporter :9115 | BU-A, BU-B, Discovery API/Web, Meilisearch (HTTP probes) | `probe_success{instance}`, `probe_duration_seconds{instance}` |
| Meilisearch native `/metrics` | enabled via `MEILI_EXPERIMENTAL_ENABLE_METRICS` | `meilisearch_index_docs_count{index}`, `meilisearch_http_requests_total{path,status}` |
| Postgres exporter BU-A :9187 | BU-A outbox table (custom SQL query) | `federation_outbox_pending{bu=bu-a}`, `_processed`, `_deadletter`, `_total`, `_oldest_pending_age_seconds` |
| Postgres exporter BU-B :9188 | BU-B outbox table | same labels `{bu=bu-b}` |

The outbox metrics directly visualize the **transactional outbox**: during initial bootstrap or automatic watchdog replay, `federation_outbox_pending` spikes to the current backlog and drains to 0 within seconds — a live demonstration of at-least-once delivery and eventual consistency.

### Grafana dashboards (http://localhost:3000, admin/admin)

Dashboards are auto-provisioned from two folders and refresh every 30 s.

#### Business folder (`monitoring/grafana/dashboards/business/`) — presentation-ready

| Dashboard | Shows | Best used for |
|---|---|---|
| **Federation Business Pulse** | Product lifecycle event counts (published/updated/deleted/unpublished), order/customer event volumes, admin business actions | Business KPI story (what changed in commerce data) |
| **Federation Demand Channels** | BU/discovery channel availability, shared-search request rate and totals, search latency | Traffic and search demand story |
| **Federation Resilience and SLA** | Endpoint availability, outbox backlog/dead-letter/age, delivered create/update/delete event signals | Operational reliability + eventual consistency story |
| **Federation BU Comparison** | Side-by-side product and order event volumes across BU-A and BU-B | Cross-BU performance comparison |

#### Federation Core folder (`monitoring/grafana/dashboards/`) — technical/operational

| Dashboard | Shows |
|---|---|
| **Pipeline E2E** | Full outbox → Kafka → Meilisearch message flow |
| **Outbox Overview** | Pending/processed/dead-letter row counts per BU |
| **Relay Overview** | KafkaRelay publish throughput and error rates |
| **Indexer Overview** | MeilisearchIndexer batch sizes and latency |
| **Search Overview** | Discovery API hit rates and Meilisearch doc count |
| **Latency** | P50/P95/P99 end-to-end event propagation |
| **Availability** | Blackbox probe success for all endpoints |
| **SSO / Keycloak** | Keycloak authentication event rates |
| **Operations** | Container health, DB connections, relay error rates |
| **Demo** | Curated composite view for live demos |

---

## Operations

### Start / stop
```bash
./platform.sh start                      # start everything
./platform.sh stop                       # stop everything
./platform.sh start --federation-only    # federation services only
./platform.sh status                     # show all container health
```

### Inspect outbox tables
```bash
# Snapshot both BUs
./platform.sh outbox

# Latest 20 rows for BU-B only
./platform.sh outbox bu-b 20

# Poll every 2 seconds to watch new rows / retries appear
./platform.sh outbox-watch all 10 2
```

### Peek Kafka events without committing offsets
```bash
# Last 10 product events from the topic tail (per partition)
./platform.sh kafka-peek federation.products 10

# Orders topic example
./platform.sh kafka-peek orders.placed 5
```

`kafka-peek` reads directly from explicit partition offsets with `enable.auto.commit=false`, so you can inspect recent events without advancing the offsets of the real workers.

### Rebuild product index after a Meilisearch volume wipe
```bash
docker compose -f docker-compose.federation.yml restart meilisearch meili-indexer kafka-relay
curl -s "http://localhost:5010/api/search?q=*"
```

The relay watchdog automatically detects an empty `products` index, resets processed product outbox rows, and republishes them within 30 s — no manual SQL required.

### View logs
```bash
docker logs nopcommerce_bua_web -f
docker logs federation_kafka_relay -f
docker logs federation_meili_indexer -f
docker logs federation_discovery_api -f
```

### Trace a product event end-to-end
```bash
# 1. Find the outbox row (check EventType column)
docker exec nopcommerce_bua_postgres psql -U nopcommerce_bua -d nopcommerce \
  -c 'SELECT "Id","EventType","EntityId","ProcessedOnUtc","Attempts" FROM "OutboxMessage" ORDER BY "CreatedOnUtc" DESC LIMIT 10;'

# 2. Check relay logs for the EventType
docker logs federation_kafka_relay --tail 50 | grep "product.deleted"

# 3. Check indexer logs
docker logs federation_meili_indexer --tail 50 | grep "bu-a-"

# 4. Verify Meilisearch
curl -s http://localhost:7700/indexes/products/stats
```

### Connect to database
```bash
docker exec -it nopcommerce_bua_postgres psql -U nopcommerce_bua -d nopcommerce
docker exec -it nopcommerce_bub_postgres psql -U nopcommerce_bub -d nopcommerce
```

### Check outbox pipeline health
```bash
# Pending rows (should drain to 0 within ~5 s)
docker exec nopcommerce_bua_postgres psql -U nopcommerce_bua -d nopcommerce \
  -c 'SELECT COUNT(*) FROM "OutboxMessage" WHERE "ProcessedOnUtc" IS NULL;'

# Dead-letter rows (Attempts >= 5)
docker exec nopcommerce_bua_postgres psql -U nopcommerce_bua -d nopcommerce \
  -c 'SELECT "Id","EventType","EntityId","Attempts","LastError" FROM "OutboxMessage" WHERE "Attempts" >= 5;'

# Meilisearch doc count
curl -s http://localhost:7700/indexes/products/stats
```

### Rebuild a service after code change
```bash
# BU-A web (after plugin change)
docker compose -f docker-compose.bua.yml build nopcommerce-bua
docker compose -f docker-compose.bua.yml up -d nopcommerce-bua

# Meilisearch indexer (after worker change)
docker compose -f docker-compose.federation.yml build meili-indexer
docker compose -f docker-compose.federation.yml up -d meili-indexer
```

---

## Development Guide

### Adding a new event type
1. Add a constant to `FederationOutboxDefaults.EventTypes`
2. Add a message record in `Federation.Contracts/`
3. Add `IConsumer<EntityXxxEvent<T>>` in the outbox plugin
4. Call `OutboxMessage.NewContext()` + `_outboxService.EnqueueAsync()`
5. Handle the new event type in `MeilisearchIndexer` (or a new worker service)

### Adding a third BU
1. Copy `docker-compose.bub.yml` → `docker-compose.buc.yml` (change ports, names, volumes)
2. Add `BUC_DB_PASS` / `BUC_ADMIN_PASS` to `.env`
3. Add `BusinessUnits__buc__*` env vars in `docker-compose.federation.yml` (relay section)
4. Add `scripts/data/seed-outbox-settings-buc.sql` and call it from `reset-and-install.sh`

### Build commands
```bash
dotnet build NopCommerce.sln -c Release                                          # full solution
dotnet build Plugins/Nop.Plugin.Federation.Outbox/... -c Release                 # outbox plugin
dotnet build FederationPlatform/Federation.KafkaRelay/... -c Release             # relay
dotnet build FederationPlatform/Federation.MeilisearchIndexer/... -c Release     # indexer
```

### Coding rules
- File-scoped namespaces; follow existing nopCommerce patterns
- `IRepository<T>`, `IEventPublisher`, `IConsumer<T>` where appropriate
- Event consumers must be **idempotent** (dedup via `MessageId`)
- Use `ILogger` / `ILogger<T>` — never `Console.WriteLine`
- No hardcoded secrets or infrastructure addresses
- Async-first, nullable-safe C# 13

See [`RULES.md`](RULES.md) for the full coding standards and [`CONTRIBUTING.md`](CONTRIBUTING.md) for the PR workflow.

---

## File Structure

```
src/
├── docker-compose.bua.yml            # BU-A stack (project: nop-bua)   port 5001/5433
├── docker-compose.bub.yml            # BU-B stack (project: nop-bub)   port 5002/5434
├── docker-compose.federation.yml     # Federation platform services
├── platform.sh                       # Unified platform CLI
├── .env / .env.example               # Credentials (gitignored)
│
├── Plugins/
│   ├── Nop.Plugin.Federation.Outbox/
│   │   ├── Domain/OutboxMessage.cs              # Entity + NewContext() factory
│   │   ├── FederationOutboxDefaults.cs          # Constants (topics, MaxAttempts=5, EventTypes)
│   │   ├── FederationOutboxSettings.cs          # ISettings — StoreCode, StoreName, Enabled, …
│   │   ├── Infrastructure/DependencyRegistrar.cs
│   │   ├── Services/IOutboxService.cs
│   │   ├── Services/OutboxService.cs            # Enqueue (idempotent) / HasAnyAsync / Purge
│   │   ├── Services/OutboxSeedStartupTask.cs    # BackgroundService — catch-up on restart
│   │   ├── Services/ProductEventConsumer.cs     # Slug URL builder + categories + logging
│   │   ├── Services/OrderEventConsumer.cs
│   │   └── Services/CustomerEventConsumer.cs
│   └── Nop.Plugin.ExternalAuth.Keycloak/
│       ├── KeycloakAuthenticationDefaults.cs
│       ├── Infrastructure/KeycloakAuthenticationRegistrar.cs
│       ├── Infrastructure/KeycloakAuthenticationEventConsumer.cs  # Name claim sync
│       ├── Infrastructure/RouteProvider.cs                         # /callback + /login-callback
│       └── Controllers/KeycloakAuthenticationController.cs
│
├── FederationPlatform/
│   ├── Federation.Contracts/                    # Shared message records (ProductChangedMessage, …)
│   ├── Federation.KafkaRelay/
│   │   ├── Program.cs                           # One RelayWorker per BU
│   │   └── Workers/RelayWorker.cs               # Outbox → Kafka + watchdog
│   ├── Federation.MeilisearchIndexer/
│   │   ├── Program.cs
│   │   └── Workers/IndexerWorker.cs             # Kafka → Meilisearch (upsert + delete)
│   ├── Federation.Discovery.Api/Program.cs      # /api/search + /api/facets + /health
│   ├── Federation.Discovery.Web/wwwroot/        # Standalone cross-BU search portal
│   ├── Federation.DiscoveryClient/              # Embedded BU widget (JS + CSS)
│   └── keycloak-realm.json                      # Realm export (auto-imported on start)
│
├── Presentation/Nop.Web/
│   ├── Dockerfile                               # Builds both plugins into the image
│   ├── Views/Home/_FederatedSearch.cshtml       # Embedded widget partial
│   └── wwwroot/lib/federated-search/            # Synced copy of DiscoveryClient assets
│
├── scripts/
│   ├── bootstrap/
│   │   ├── reset-and-install.sh                 # Generic install orchestrator
│   │   ├── reset-and-install-bu.sh              # BU-specific wrapper
│   │   ├── auto-install-http.sh                 # HTTP installer client
│   │   ├── auto-install.Dockerfile
│   │   └── postgres-init-extensions.sh          # citext extension hook
│   └── data/
│       ├── init-outbox-schema.sql               # Outbox table DDL
│       ├── split-by-category.sh                 # Catalogue split + branding
│       ├── seed-outbox-settings-bua.sql         # FederationOutboxSettings for BU-A
│       └── seed-outbox-settings-bub.sql         # FederationOutboxSettings for BU-B
│
├── monitoring/
│   ├── docker-compose.prometheus.yml            # Prometheus + Grafana + Blackbox + 2× PG exporter
│   ├── prometheus/prometheus.yml                # Scrape jobs
│   ├── postgres-exporter/queries.yaml           # Custom outbox metrics SQL
│   └── grafana/
│       ├── provisioning/                        # Datasource + dashboard providers
│       └── dashboards/                          # 14 auto-provisioned JSON dashboards (10 core + 4 business)
│
├── docs/
│   ├── demo_playbook.md                         # Step-by-step demo runbook
│   └── diagrams.md                              # 9 Mermaid diagrams (C4, sequences, state, …)
│
└── LICENSE.md
```

---

*Last updated: 2026-06-03*
