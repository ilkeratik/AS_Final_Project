# Federation Platform — Demo Playbook

Last updated: 2026-06-03

---

## Purpose

This playbook demonstrates three federation capabilities in a live session:

| Scenario | What it proves |
|---|---|
| **A — Baseline** | Cross-BU federated search works end-to-end |
| **B — Fault isolation** | BU-A failure does not affect BU-B or Discovery |
| **C — Auto-recovery** | Transactional outbox ensures eventual consistency after BU restart |

Diagrams for each flow are in [`docs/diagrams.md`](diagrams.md).

---

## Prerequisites

All services up and healthy:

```bash
cd /Users/ilker/RiderProjects/nopCommerce/src
./platform.sh start --no-build
./platform.sh status
```

Expected: all containers show `healthy` or `running`.

---

## Scenario A — Baseline Federated Discovery

### A1 · Confirm product index

```bash
curl -s 'http://localhost:5010/api/search?q=*' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('totalHits =', d.get('totalHits'), '|', d.get('hits',[{}])[0].get('storeName',''),'…')"
```

Expected: `totalHits` reflects the current combined published catalogue.

### A2 · Open browser tabs

| Tab | URL | Shows |
|---|---|---|
| BU-A storefront | http://localhost:5001 | HomeStyle Living |
| BU-B storefront | http://localhost:5002 | WorkForge Industrial |
| Discovery Web | http://localhost:5011 | Cross-BU search portal |
| Grafana | http://localhost:3000 | admin/admin → **Federation Operations Summary** |

### A3 · Search across both BUs

1. Open **Discovery Web** (http://localhost:5011)
2. Type a search term (e.g. `"table"` or `"drill"`)
3. Results show hits from **both** BU-A and BU-B
4. Click "View ↗" — opens the product page on the originating storefront

### A4 · Publish a new product (live event demo)

1. Log in to BU-A admin (http://localhost:5001/admin)
2. Catalog → Products → Add New → fill Name + Price → Save
3. Watch Grafana **Outbox Overview**: `federation_outbox_pending` spikes then drains to 0
4. Within ~8 s the product appears in Discovery Web search

### A5 · Delete a product (live delete demo)

1. In BU-A admin, delete the product you just created (or set Published = false)
2. Grafana **Outbox Overview** shows another brief spike
3. Within ~8 s the product disappears from Discovery Web — no manual cleanup needed

---

## Scenario B — Fault Isolation (BU-A degraded)

### B1 · Pause BU-A database

```bash
./scripts/demo/pause_bua.sh
```

### B2 · Verify isolation

| Check | Expected |
|---|---|
| `curl -I http://localhost:5001` | 5xx / connection refused |
| `curl -I http://localhost:5002` | **200** — BU-B fully isolated |
| `curl -s 'http://localhost:5010/api/search?q=*'` | Returns BU-B results — Discovery still works |
| Grafana **Operations Summary** | BU-A probe turns **red**; everything else stays **green** |

### B3 · Run load during degradation (optional)

```bash
./scripts/demo/load_test.sh 20 15
# 20 concurrent users, 15 seconds
```

Discovery API continues serving from Meilisearch — no dependency on the live BU-A runtime.

---

## Scenario C — Auto-recovery + Eventual Consistency

### C1 · Resume BU-A

```bash
./scripts/demo/resume_bua.sh
docker compose -f docker-compose.bua.yml restart nopcommerce-bua
```

### C2 · Watch the outbox replay

```bash
docker logs -f federation_meili_indexer
# or watch in Grafana → Federation Outbox Overview
```

Expected sequence:
1. `federation_outbox_pending{bu=bu-a}` **spikes** as the seed service re-enqueues missed events
2. Relay processes the backlog: `federation_outbox_pending` **drains to 0** within ~5 s
3. `meilisearch_index_docs_count` returns to the full combined count

### C3 · Confirm full recovery

```bash
curl -s 'http://localhost:5010/api/search?q=*' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('totalHits =', d.get('totalHits'))"
# Expected: same count as before degradation
```

Grafana **Operations Summary**: all services green, outbox pending = 0.

---

## SSO Demo (optional)

1. Open BU-A storefront (http://localhost:5001)
2. Click **Login** → **Sign in with SSO**
3. Keycloak login page opens at http://localhost:8080
4. Sign in (or register a new account)
5. Redirected back to BU-A — authenticated ✅
6. Open BU-B (http://localhost:5002) → **Login** → **Sign in with SSO**
7. **Already authenticated** — same Keycloak session, no password prompt ✅

---

## Grafana Dashboards Reference

Open http://localhost:3000 (admin/admin):

| Dashboard | Best moment to show |
|---|---|
| **Federation Operations Summary** | Always — the "one screen" story |
| **Federation Outbox Overview** | Scenario A4/A5 (publish/delete spike) and C2 (replay drain) |
| **Federation Availability** | Scenario B (BU-A red, rest green) |
| **Federation Relay Overview** | Relay throughput during backlog drain |
| **Federation Indexer Overview** | `meilisearch_index_docs_count` recovery |
| **Federation Search Engine** | Request rate from Discovery API queries |

All dashboards use **real metrics** and refresh every 5 s.

---

## Cleanup

```bash
./platform.sh stop
```

---

## Safety Notes

- Only run these steps in the development environment.
- Do not pause production databases.
- BU web restarts are a demo shortcut; production replay should remain event-driven.

---

## Files Referenced

| File | Purpose |
|---|---|
| `docs/demo_playbook.md` | This file |
| `docs/diagrams.md` | 9 Mermaid architecture diagrams |
| `scripts/demo/pause_bua.sh` | Pause BU-A postgres container |
| `scripts/demo/resume_bua.sh` | Resume BU-A postgres container |
| `scripts/demo/load_test.sh` | Concurrent load against Discovery API |
| `monitoring/grafana/dashboards/` | 8 auto-provisioned Grafana dashboards |

---

*Last updated: 2026-06-03*
