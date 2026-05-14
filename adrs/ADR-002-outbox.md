# ADR 002: Application-Level Transactional Outbox

Status: Proposed

## Context
When a service attempts to write to its local database and synchronously publish an event to a broker, the system is vulnerable to the dual-write problem: database commit success combined with broker failure yields inconsistency. The architecture must guarantee reliable event publishing without blocking local transactions.

## Decision
Adopt the Application-Level Transactional Outbox pattern: persist outgoing events to an `Outbox` table in the same ACID transaction as domain writes. Run a separate relay service to publish outbox records to Apache Kafka and mark them processed.

## Consequences
- Positive:
	- Ensures atomicity between domain changes and event persistence.
	- Local operations remain responsive even when downstream systems are degraded.
- Negative:
	- Requires operational management of outbox backlog, retention, and retries.
	- Downstream consumers must be idempotent or deduplicate events.

## Alternatives
- Use a CDC tool (e.g., Debezium) to capture DB changes and stream them — considered but rejected due to higher operational complexity and cross-platform constraints.

## Date
2026-05-14

## Authors
Integration Architecture Team

## Related
See ADR-001 (Single-Store) and ADR-003 (Discovery)
