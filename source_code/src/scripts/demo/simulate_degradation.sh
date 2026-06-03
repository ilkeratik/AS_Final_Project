#!/usr/bin/env bash
# Lightweight end-to-end demo: pause BU-A DB, run read load, unpause and optionally replay outbox
# Usage: ./scripts/demo/simulate_degradation.sh [concurrency=50] [duration_seconds=30]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CONCURRENCY=${1:-50}
DURATION=${2:-30}
BUA_CONTAINER=${BUA_CONTAINER:-nopcommerce_bua_postgres}

pause_bua() {
  echo "Pausing BU-A Postgres container: $BUA_CONTAINER"
  docker pause "$BUA_CONTAINER"
}

resume_bua() {
  echo "Unpausing BU-A Postgres container: $BUA_CONTAINER"
  docker unpause "$BUA_CONTAINER"
}

cleanup() {
  # best-effort resume on exit
  echo "Demo finished or interrupted; ensuring BU-A is unpaused"
  docker unpause "$BUA_CONTAINER" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

pause_bua
echo "Running load test (concurrency=$CONCURRENCY duration=${DURATION}s) while BU-A is degraded"
"${PROJECT_ROOT}/scripts/demo/load_test.sh" "$CONCURRENCY" "$DURATION"

resume_bua

echo "BU-A is back. The Outbox hosted service will re-seed any missing events on next app boot."
echo "To trigger immediately, restart the BU-A web container:"
echo "  docker compose -f docker-compose.bua.yml restart nopcommerce-bua"

echo "Tailing indexer logs to observe reconciliation (Ctrl+C to stop)"
docker logs -f federation_meili_indexer


