# ADR-002: Application-Level Transactional Outbox Pattern

## Status
Proposed

## Context
Synchronous dual-write (database + broker) leads to inconsistent states when network or broker failures occur. The system must guarantee at-least-once delivery of domain events without blocking local transactions.

## Decision
Implement an Application-Level Transactional Outbox: persist outgoing event payloads to a local `Outbox` table in the same ACID transaction as the domain write; use a background relay to publish to Apache Kafka and mark records processed.

## Consequences
- Pros:
  - Atomicity between domain write and event persist.
  - Local storefront remains responsive when downstream systems are degraded.
- Cons:
  - Must implement pruning/retention and deduplication strategies.
  - Operational responsibility for relay/backpressure handling.

## Rationale
This pattern converts a distributed transaction into a safe local transaction and provides explicit reliability guarantees while minimizing new infrastructure components.

## Implementation notes
- Include correlation IDs and headers for tracing.
- Ensure idempotency of downstream consumers.
- Monitor outbox backlog, implement alerting when backlog thresholds are exceeded.

## References
See main document: `AS Final Assignment.md` (Section 7.2)
