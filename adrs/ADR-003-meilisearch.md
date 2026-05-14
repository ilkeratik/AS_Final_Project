# ADR-003: Centralized Discovery via Meilisearch Asynchronous Materialized Views (Open-Host Service)

## Status
Proposed

## Context
Cross-database SQL queries between physically isolated BU databases are prohibited. The enterprise requires a unified discovery/search experience across brands.

## Decision
Use Meilisearch as the centralized Group Discovery Context. Each BU publishes `ProductUpdatedEvent` payloads to Kafka (Open-Host Service). A downstream indexer consumes these events, applies ACL transformations, and projects documents into Meilisearch.

## Consequences
- Pros:
  - Low operational overhead and strong out-of-the-box relevancy for e-commerce.
  - Enables federated discovery without direct DB coupling.
- Cons:
  - Eventual consistency (propagation delay up to the agreed window).
  - Additional indexer component to normalize and project events.

## Rationale
Meilisearch balances operational simplicity and relevancy; Kafka and the outbox pattern provide the durable, decoupled event stream needed for safe aggregation.

## Trade-offs
Accepts delayed consistency (up to configured SLA, e.g., 2 minutes) in favor of fault isolation.

## References
See main document: `AS Final Assignment.md` (Section 7.3)
