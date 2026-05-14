# ADR-001: Single-Store Deployment Configuration

Status: Proposed

Context
The nopCommerce platform includes a native multi-store capability that can host multiple storefronts from a single application and shared database. The federated acquisition scenario requires strict fault isolation between business units (BUs) and forbids shared-database shortcuts across BU boundaries.

Decision
Deploy each BU as an independent nopCommerce runtime with its own dedicated PostgreSQL database. Do not use the shared multi-store database for cross-BU operation; keep the multi-store code but disable/use single-store configuration per deployment.

Consequences
- Positive: strong fault isolation, independent scaling and upgrades, clearer operational ownership.
- Negative: higher operational overhead (multiple DBs and runtimes); cross-BU aggregation requires asynchronous approaches (search index, event streams).

Alternatives Considered
- Use shared multi-store with strict tenant isolation (rejected: shared DB remains single point of failure).
- Use logical tenancy (tenant_id) in one DB (rejected for compliance and risk reasons).

Date: 2026-05-14
Owners: Platform Architecture Team / DevOps
