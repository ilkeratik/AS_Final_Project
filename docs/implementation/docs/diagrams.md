# Federation Platform — Architecture Diagrams

Last updated: 2026-06-03

All diagrams use [Mermaid](https://mermaid.js.org/) syntax and render natively on GitHub, GitLab, and most modern Markdown viewers.

---

## 1 · System Context (C4 Level 1)

```mermaid
graph TB
    subgraph Shopper["👤 Shopper"]
        S1[Browser / App]
    end

    subgraph Federation["nopCommerce Federated Commerce Platform"]
        subgraph BUA["BU-A · HomeStyle Living · :5001"]
            BUA_WEB["nopCommerce Web\n+ Outbox Plugin\n+ Keycloak Plugin"]
            BUA_DB[("PostgreSQL :5433")]
            BUA_WEB -- "INSERT OutboxMessage (same tx)" --> BUA_DB
        end

        subgraph BUB["BU-B · WorkForge Industrial · :5002"]
            BUB_WEB["nopCommerce Web\n+ Outbox Plugin\n+ Keycloak Plugin"]
            BUB_DB[("PostgreSQL :5434")]
            BUB_WEB -- "INSERT OutboxMessage (same tx)" --> BUB_DB
        end

        subgraph EventBackbone["Event Backbone"]
            RELAY["Kafka Relay\n(polls every 5 s)"]
            KAFKA["Apache Kafka :9092\nfederation.products\norders.placed / customers.created"]
            INDEXER["Meilisearch Indexer\nconsumer: federation-indexer"]
        end

        subgraph Discovery["Shared Discovery"]
            MEILI[("Meilisearch :7700\nproducts index")]
            API["Discovery API :5010\nGET /api/search\nGET /api/facets"]
            WEB["Discovery Web :5011\nCross-BU search UI"]
        end

        KC["Keycloak :8080\nOIDC IdP — realm: nop-federation"]

        subgraph Observability["Observability"]
            PROM["Prometheus :9090"]
            GRAF["Grafana :3000\n8 dashboards"]
        end
    end

    BUA_DB -- "FOR UPDATE SKIP LOCKED" --> RELAY
    BUB_DB -- "FOR UPDATE SKIP LOCKED" --> RELAY
    RELAY -- "Acks=All, Idempotent" --> KAFKA
    KAFKA -- "consume" --> INDEXER
    INDEXER -- "bulk upsert / delete" --> MEILI
    MEILI --> API
    API --> WEB

    S1 -- "shop" --> BUA_WEB
    S1 -- "shop" --> BUB_WEB
    S1 -- "federated search" --> WEB
    S1 -- "SSO login" --> KC
    KC -- "OIDC callback" --> BUA_WEB
    KC -- "OIDC callback" --> BUB_WEB

    BUA_DB -.->|"outbox metrics"| PROM
    BUB_DB -.->|"outbox metrics"| PROM
    MEILI -.->|"native /metrics"| PROM
    BUA_WEB -.->|"HTTP probe"| PROM
    BUB_WEB -.->|"HTTP probe"| PROM
    PROM --> GRAF
```

---

## 2 · Transactional Outbox — Message State Machine

```mermaid
stateDiagram-v2
    [*] --> Pending : nopCommerce event fires\nProductEventConsumer.EnqueueAsync()

    Pending --> Relaying : KafkaRelay batch poll\n(FOR UPDATE SKIP LOCKED)

    Relaying --> Processed : Kafka PersistenceStatus.Persisted\nProcessedOnUtc = NOW()

    Relaying --> Pending : Kafka error — Attempts += 1

    Pending --> DeadLetter : Attempts ≥ MaxAttempts (5)\nrow skipped by relay query

    Processed --> Purged : PurgeProcessedAsync()\nProcessedOnUtc < NOW() - 7 days

    DeadLetter --> Pending : Operator reset\nAttempts = 0, LastError = NULL

    Processed --> Pending : Watchdog recovery\n(Meilisearch index unexpectedly empty)
```

---

## 3 · Product Lifecycle — Publish & Delete Flow

```mermaid
sequenceDiagram
    actor Admin
    participant NopWeb as nopCommerce Web
    participant Consumer as ProductEventConsumer
    participant OutboxSvc as OutboxService
    participant OutboxDB as OutboxMessage (PG)
    participant Relay as KafkaRelay
    participant Kafka as Kafka Broker
    participant Indexer as MeilisearchIndexer
    participant Meili as Meilisearch
    participant DiscAPI as Discovery API
    actor Shopper

    Note over Admin,OutboxDB: ── PUBLISH path (product.published / product.updated) ──
    Admin->>NopWeb: Save product (create or edit)
    NopWeb->>Consumer: EntityInsertedEvent or EntityUpdatedEvent
    Consumer->>Consumer: Fetch slug + categories + thumbnail (parallel)
    Consumer->>OutboxSvc: EnqueueAsync(EventType=product.published)
    OutboxSvc->>OutboxDB: INSERT — idempotent (skip if MessageId exists)

    Relay->>OutboxDB: SELECT ≤50 pending rows FOR UPDATE SKIP LOCKED
    Relay->>Kafka: ProduceAsync(federation.products, Acks=All)
    Kafka-->>Relay: PersistenceStatus.Persisted
    Relay->>OutboxDB: UPDATE ProcessedOnUtc = NOW()

    Indexer->>Kafka: consume federation.products (batch ≤50 / 500 ms)
    Indexer->>Meili: AddDocumentsAsync(id="bu-a-42")
    Meili-->>Indexer: task accepted

    Shopper->>DiscAPI: GET /api/search?q=armchair
    DiscAPI->>Meili: search
    Meili-->>DiscAPI: hits (includes bu-a-42)
    DiscAPI-->>Shopper: {"totalHits":5, "hits":[…]}

    Note over Admin,OutboxDB: ── DELETE / UNPUBLISH path (product.deleted / product.unpublished) ──
    Admin->>NopWeb: Delete or unpublish product
    NopWeb->>Consumer: EntityUpdatedEvent{Deleted=true or Published=false}
    Consumer->>OutboxSvc: EnqueueAsync(EventType=product.deleted)
    OutboxSvc->>OutboxDB: INSERT

    Relay->>OutboxDB: next poll picks up delete row
    Relay->>Kafka: ProduceAsync(EventType=product.deleted)
    Relay->>OutboxDB: UPDATE ProcessedOnUtc = NOW()

    Indexer->>Kafka: consume — EventType=product.deleted detected
    Indexer->>Meili: DeleteDocumentsAsync(["bu-a-42"])
    Meili-->>Indexer: task accepted

    Note over Meili,Shopper: Next search no longer returns bu-a-42 ✅
```

---

## 4 · SSO Login Flow (Keycloak OIDC)

```mermaid
sequenceDiagram
    actor Shopper
    participant BU as BU Storefront
    participant OIDC as OIDC Middleware\n(/keycloakauthentication/callback)
    participant KC as Keycloak :8080
    participant Ctrl as KeycloakAuthenticationController\n(/login-callback)
    participant NopAuth as IExternalAuthenticationService

    Shopper->>BU: Click "Login with SSO"
    BU->>OIDC: Trigger OIDC challenge
    OIDC-->>Shopper: 302 → /authorize?client_id=bu-a-client&state=…

    Shopper->>KC: Submit credentials
    KC->>KC: Validate, issue id_token + access_token

    KC-->>Shopper: 302 → /keycloakauthentication/callback?code=…
    Shopper->>OIDC: GET /keycloakauthentication/callback
    OIDC->>KC: POST /token (code exchange)
    KC-->>OIDC: id_token (given_name, family_name, email, sub)

    OIDC-->>Shopper: 302 → /keycloakauthentication/login-callback
    Shopper->>Ctrl: GET /keycloakauthentication/login-callback
    Ctrl->>Ctrl: Map given_name→FirstName, family_name→LastName
    Ctrl->>NopAuth: AuthenticateAsync(externalAuthInfo)
    NopAuth->>NopAuth: Find or create Customer record
    NopAuth-->>Ctrl: success

    Ctrl-->>Shopper: Redirect to returnUrl (authenticated session ✅)
    Note over Shopper,KC: Same Keycloak account works on both BU-A and BU-B (SSO)
```

---

## 5 · Kafka Relay — Reliability Loop

```mermaid
flowchart TD
    Start([Relay starts]) --> Init[Init Kafka producer\nAcks=All · Idempotent\nRetries=5]
    Init --> CheckWD{Watchdog\ndue?}

    CheckWD -- Yes --> WD[CheckAndRestoreIndexAsync]
    WD --> WD1{Meilisearch index\nempty?}
    WD1 -- No --> Poll
    WD1 -- Yes --> WD2{Processed product\nrows in outbox?}
    WD2 -- No --> WD3[Fresh install detected\nlog + skip]
    WD3 --> Poll
    WD2 -- Yes --> WD4["Reset ProcessedOnUtc=NULL\nAttempts=0 for product rows\n(re-publish trigger)"]
    WD4 --> Poll

    CheckWD -- No --> Poll["BEGIN TRANSACTION\nSELECT ≤50 pending rows\nFOR UPDATE SKIP LOCKED"]
    Poll --> Empty{Rows\nfound?}
    Empty -- No --> Wait[Rollback TX\nWait 5 s + jitter]
    Wait --> CheckWD

    Empty -- Yes --> ForEach["For each row:\nlog EventType + EntityId\nProduceAsync → Kafka"]
    ForEach --> Delivered{PersistenceStatus\n.Persisted?}
    Delivered -- Yes --> Mark["UPDATE ProcessedOnUtc=NOW()\nlog 'Kafka persisted'"]
    Delivered -- No --> Bump[UPDATE Attempts+=1\nLastError=status\nlog warning]
    Mark --> NextRow{More\nrows?}
    Bump --> NextRow
    NextRow -- Yes --> ForEach
    NextRow -- No --> Commit[COMMIT TX\nlog batch summary\npublished + failed counts]
    Commit --> CheckWD
```

---

## 6 · Degraded BU Scenario + Automatic Recovery

```mermaid
sequenceDiagram
    actor Ops
    participant BUA_DB as BU-A PostgreSQL
    participant BUA_WEB as BU-A nopCommerce
    participant BUB_DB as BU-B PostgreSQL
    participant Relay as KafkaRelay
    participant Kafka as Kafka Broker
    participant Indexer as MeilisearchIndexer
    participant Meili as Meilisearch
    participant DiscAPI as Discovery API
    actor Shopper

    Note over BUA_DB,BUA_WEB: ⚠️ BU-A database paused
    Ops->>BUA_DB: docker pause postgres-bua

    BUA_WEB->>BUA_DB: ❌ Connection refused
    Note over BUA_WEB: BU-A returns 5xx / unhealthy

    Note over BUB_DB,Relay: BU-B continues unaffected
    BUB_DB-->>Relay: poll returns BU-B rows only
    Relay->>Kafka: produce BU-B events
    Kafka->>Indexer: consume BU-B events
    Indexer->>Meili: upsert BU-B documents

    Shopper->>DiscAPI: GET /api/search?q=workbench
    DiscAPI->>Meili: search (BU-A data stale, BU-B fresh)
    DiscAPI-->>Shopper: partial results — BU-B only ⚠️

    Note over BUA_DB,BUA_WEB: ✅ BU-A restored
    Ops->>BUA_DB: docker unpause postgres-bua
    Ops->>BUA_WEB: restart nopcommerce-bua

    BUA_WEB->>BUA_WEB: OutboxSeedHostedService boots\ndetects unrelayed products
    BUA_WEB->>BUA_DB: INSERT missing OutboxMessage rows
    BUA_DB-->>Relay: next poll picks up BU-A backlog
    Relay->>Kafka: produce BU-A events (idempotent replay)
    Kafka->>Indexer: consume BU-A messages
    Indexer->>Meili: upsert BU-A documents

    Shopper->>DiscAPI: GET /api/search?q=workbench
    DiscAPI->>Meili: search
    Meili-->>DiscAPI: full cross-BU hits
    DiscAPI-->>Shopper: ✅ complete results restored
```

---

## 7 · Observability Stack

```mermaid
graph LR
    subgraph Targets["Probe Targets"]
        BUA_H["BU-A :5001"]
        BUB_H["BU-B :5002"]
        DISC_H["Discovery API :5010"]
        WEB_H["Discovery Web :5011"]
        MEILI_H["Meilisearch :7700"]
    end

    subgraph DBs["PostgreSQL Outbox Tables"]
        BUA_DB[("BU-A Postgres\nOutboxMessage")]
        BUB_DB[("BU-B Postgres\nOutboxMessage")]
    end

    subgraph Exporters["Exporters"]
        BB["Blackbox Exporter :9115\nprobe_success\nprobe_duration_seconds"]
        PGA["Postgres Exporter :9187\nfederation_outbox_pending{bu-a}\nfederation_outbox_processed\nfederation_outbox_deadletter\nfederation_outbox_oldest_age_seconds"]
        PGB["Postgres Exporter :9188\nfederation_outbox_pending{bu-b}\n…same metrics…"]
        MEILI_NATIVE["Meilisearch /metrics\nmeilisearch_index_docs_count\nmeilisearch_http_requests_total"]
    end

    PROM["Prometheus :9090\n15 s scrape interval"]
    GRAF["Grafana :3000\n8 dashboards · 5 s refresh"]

    BUA_H --> BB
    BUB_H --> BB
    DISC_H --> BB
    WEB_H --> BB
    MEILI_H --> BB
    BUA_DB --> PGA
    BUB_DB --> PGB
    MEILI_H --> MEILI_NATIVE

    BB --> PROM
    PGA --> PROM
    PGB --> PROM
    MEILI_NATIVE --> PROM
    PROM --> GRAF
```

---

## 8 · OutboxMessage Schema

```mermaid
erDiagram
    OutboxMessage {
        int      Id              PK
        varchar  MessageId       UK  "storeCode.eventType.entityId.utcTicks"
        varchar  StoreCode           "bu-a or bu-b"
        varchar  StoreName
        varchar  EventType           "product.published/updated/deleted/unpublished"
        varchar  Topic               "federation.products etc."
        text     Payload             "JSON — ProductChangedMessage / OrderPlacedMessage"
        varchar  CorrelationId       "UUID for distributed tracing via Kafka headers"
        int      EntityId            "Product.Id / Order.Id / Customer.Id"
        int      Attempts            "0–5; row skipped when Attempts >= MaxAttempts(5)"
        varchar  LastError       nullable
        datetime CreatedOnUtc
        datetime ProcessedOnUtc  nullable "NULL = pending"
    }
```

---

## 9 · Meilisearch Document ID Addressing

```mermaid
graph LR
    subgraph BUA["BU-A — HomeStyle Living"]
        P1["Product #4\nArmchair"] --> D1["id: bu-a-4"]
        P2["Product #12\nBedding Set"] --> D2["id: bu-a-12"]
    end

    subgraph BUB["BU-B — WorkForge Industrial"]
        P3["Product #7\nAngle Grinder"] --> D3["id: bu-b-7"]
        P4["Product #23\nSafety Helmet"] --> D4["id: bu-b-23"]
    end

    D1 & D2 & D3 & D4 --> IDX[("Meilisearch\nproducts index")]

    IDX --> DISC["Discovery API\nGET /api/search?q=*\nGET /api/facets"]

    DISC --> RES["Cross-BU results\n{ storeCode, storeName,\n  productName, productUrl }"]
```

> **Isolation guarantee:** `DeleteDocumentsAsync(["bu-b-23"])` only removes BU-B's product 23.  
> BU-A documents can never be accidentally deleted by a BU-B event.

---

*Last updated: 2026-06-03*
