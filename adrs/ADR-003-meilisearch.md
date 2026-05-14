# ADR 003: Centralized Discovery via Meilisearch

Status: Proposed

## Context
Business Units (BUs) run isolated transactional databases; executing cross-database queries is disallowed. The enterprise requires a single discovery/search experience that aggregates catalogs from all BUs while preserving BU autonomy.

## Decision
Use Meilisearch as the centralized Group Discovery index. Each BU publishes `ProductUpdatedEvent` messages to Kafka (via the Outbox pattern); a downstream indexer consumes events, applies normalization/ACL transforms, and indexes documents into Meilisearch.

## Consequences
- Positive:
	- Decouples discovery from transactional systems and provides a fast, relevance-tuned search experience.
	- Lower operational overhead compared to heavy Lucene clusters for basic e-commerce search.
- Negative:
	- Eventual consistency: updates propagate with a delay determined by the pipeline and SLA.
	- Requires running and monitoring an indexer component.

## Alternatives
- Use OpenSearch/Elasticsearch for richer feature set (rejected here due to higher operational cost and complexity).
- Implement a federated synchronous gateway that queries BUs at runtime (rejected due to coupling and availability risk).

## Date
2026-05-14

## Authors
Search & Discovery Team

## Related
See ADR-002 (Outbox) and ADR-001 (Single-Store)
