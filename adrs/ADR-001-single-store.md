# ADR-001: Single-Store Deployment Configuration over Native Multi-Store Routing

## Status
Proposed

## Context
nopCommerce includes a native multi-store capability that routes multiple storefronts from a single application and shared database. The federated scenario requires strict fault boundaries between business units (BUs) to avoid a single shared-database shortcut across extracted service boundaries.

## Decision
Deploy each business unit as an independent nopCommerce runtime with a dedicated PostgreSQL database. Do not operationally use the native multi-store shared-database feature for cross-brand integration. The native multi-store code remains in the codebase (not removed).

## Consequences
- Pros:
  - Strong fault isolation and local autonomy.
  - Independent scaling, maintenance, and upgrades per BU.
- Cons:
  - More infrastructure to operate (multiple app instances and DBs).
  - Cross-brand queries require asynchronous aggregation (e.g., search index).

## Rationale
The federated scenario explicitly forbids shared DB shortcuts. Operational isolation prevents a localized failure from cascading across brands, meeting the "local degradation without group collapse" quality attribute.

## References
See main document: `AS Final Assignment.md` (Section 7.1)
