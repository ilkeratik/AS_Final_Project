# ADR 001: Single-Store Deployment Configuration

Status: Proposed

## Context
nopCommerce supports a native multi-store mode that runs multiple storefronts from a single application and shared database. In the federated acquisitions scenario the business requires strict fault isolation and independent operational control per Business Unit (BU). Shared-database shortcuts across BU boundaries are disallowed by policy.

## Decision
Each BU will be deployed as an independent nopCommerce runtime backed by its own PostgreSQL database. The native multi-store code remains in the codebase but deployments will be configured for single-store operation (multi-store routing disabled for cross-BU use).

## Consequences
- Positive:
	- Strong fault isolation and local autonomy per BU.
	- Independent scaling, upgrades, and maintenance per BU.
- Negative:
	- Increased operational footprint (multiple application instances and databases).
	- Cross-BU aggregation requires asynchronous approaches (e.g., centralized search index) rather than direct SQL.

## Alternatives
- Use nopCommerce multi-store with strict application-layer tenant isolation — rejected because the shared DB remains a single point of failure.
- Use logical tenancy (tenant_id) in a single database — rejected due to compliance and fault-domain concerns.

## Date
2026-05-14

## Authors
Platform Architecture Team

## Related
See ADR-002 (Outbox) and ADR-003 (Discovery)
