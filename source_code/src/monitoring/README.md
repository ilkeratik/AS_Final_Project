Last updated: 2026-06-02

Monitoring stack (Prometheus + Grafana + exporters)
===================================================

A lightweight, demo-ready observability stack that exposes **real metrics** for the
federation platform without changing any application code. Started automatically by
`./platform.sh start` (or standalone below).

Start standalone:

```bash
cd /Users/ilker/RiderProjects/nopCommerce/src
docker compose -f monitoring/docker-compose.prometheus.yml up -d
```

Open:
- Prometheus: http://localhost:9090
- Grafana:    http://localhost:3000  (admin/admin)

Components
---------
| Container | Purpose |
|---|---|
| `federation_prometheus_1` | scrapes all exporters (15 s interval) |
| `federation_grafana_1` | dashboards, auto-provisioned |
| `federation_blackbox_1` | HTTP probes of BU/Discovery/Meilisearch |
| `federation_pg_exporter_bua` | BU-A outbox metrics (port 9187) |
| `federation_pg_exporter_bub` | BU-B outbox metrics (port 9188) |

Metric sources
--------------
1. **Blackbox probes** (job `blackbox-probes`) — `probe_success`, `probe_duration_seconds`
   for BU-A (5001), BU-B (5002), Discovery API (5010/health), Discovery Web (5011),
   Meilisearch (7700/health). One series per `instance`.

2. **Meilisearch native metrics** (job `meilisearch`, needs `MEILI_EXPERIMENTAL_ENABLE_METRICS=true`):
   `meilisearch_index_docs_count{index}`, `meilisearch_http_requests_total{path,status}`.

3. **Postgres exporters** (jobs `outbox-bua` / `outbox-bub`, custom query in
   `postgres-exporter/queries.yaml`): `federation_outbox_pending/processed/deadletter/total/oldest_pending_age_seconds{bu}`.

Dashboards (`grafana/dashboards/`, auto-provisioned)
----------------------------------------------------
- **Federation Operations Summary** — one-screen exec view (availability + outbox + docs + latency)
- **Federation Demo Overview** — probe success + latency
- **Federation Availability** — per-service up/down
- **Federation Latency** — probe durations
- **Federation Outbox Overview** — pending/processed/dead-letter/age per BU
- **Federation Relay Overview** — publish throughput + backlog
- **Federation Indexer Overview** — Meilisearch doc count + request rate
- **Federation Search Engine (Meilisearch)** — request rate by status/path

Demo tie-in
-----------
During initial bootstrap, relay watchdog recovery, or the degradation demo, watch
**Federation Outbox Overview**: `federation_outbox_pending` spikes to the current backlog
then drains to 0 within ~5 s as the relay republishes — a live, real-data demonstration
of the transactional outbox + eventual consistency.

Useful Prometheus expressions
-----------------------------
- `probe_success{job="blackbox-probes"} == 0`   # failing endpoints
- `federation_outbox_pending`                    # backlog per BU
- `rate(federation_outbox_processed[1m])`        # relay publish throughput
- `meilisearch_index_docs_count`                 # cross-BU indexed docs

Notes
-----
- Intentionally lightweight for demos. Probes use `host.docker.internal` (Docker Desktop).
- DB passwords are read from `.env` via Compose interpolation (`BUA_DB_PASS` / `BUB_DB_PASS`).
- For production: run exporters on the overlay network, secure Grafana, add a Kafka
  exporter for broker/consumer-lag metrics, and instrument the .NET workers directly.

