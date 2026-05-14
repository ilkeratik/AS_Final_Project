# ADR-003: Centralized Discovery via Meilisearch

Status: Proposed

Context
Federated BUs are deployed with isolated databases; cross-database SQL is prohibited. The enterprise requires a unified discovery/search experience across brands without coupling transactional systems.

Decision
Use Meilisearch as the centralized Group Discovery index. BUs publish `ProductUpdatedEvent` messages to Kafka; a downstream indexer consumes events, normalizes documents, and indexes them into Meilisearch.

Consequences
- Positive: low operational overhead, good relevancy for e-commerce, decoupled aggregation.
- Negative: eventual consistency (document propagation delay) and an additional indexer component to operate.

Alternatives Considered
- Use OpenSearch/Elasticsearch (higher operational cost) or run a federated synchronous gateway (rejected for coupling risk).

Date: 2026-05-14
Owners: Search & Discovery Team / Platform Integration Team
