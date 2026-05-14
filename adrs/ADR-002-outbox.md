# ADR-002: Application-Level Transactional Outbox

Status: Proposed

Context
Publishing events to an external broker during the same operation as a domain write creates a dual-write problem that can lead to inconsistency when network or broker failures occur.

Decision
Persist outgoing event payloads to a local `Outbox` table within the same ACID transaction as the domain write; run a separate relay process that publishes outbox entries to Apache Kafka and marks them processed.

Consequences
- Positive: atomicity between domain write and event persist; storefront remains responsive when downstream systems are degraded.
- Negative: requires operational handling of outbox backlog, pruning policy, and consumer idempotency.

Alternatives Considered
- Use CDC (Debezium) to stream DB changes (rejected for operational complexity).

Date: 2026-05-14
Owners: Integration Architecture Team / Backend Services Team
