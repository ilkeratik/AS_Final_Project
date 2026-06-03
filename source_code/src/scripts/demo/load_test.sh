#!/usr/bin/env bash
# Lightweight concurrent load tester (POSIX-ish bash)
# Usage: ./scripts/demo/load_test.sh [concurrency=50] [duration_seconds=30]

set -euo pipefail

CONCURRENCY=${1:-50}
DURATION=${2:-30}
API_BASE=${API_BASE:-http://localhost:5010}
DISCOVERY_URL="$API_BASE/api/search?q=*"

echo "Starting load test: concurrency=$CONCURRENCY duration=${DURATION}s discovery=$DISCOVERY_URL"
end_time=$((SECONDS + DURATION))

pids=()
worker() {
  while [ $SECONDS -lt $end_time ]; do
    curl -sS -o /dev/null -w "%{http_code} %{time_total} discovery\n" "$DISCOVERY_URL" || true
    if [ $((RANDOM % 2)) -eq 0 ]; then
      curl -sS -o /dev/null -w "%{http_code} %{time_total} bua\n" "http://localhost:5001/" || true
    else
      curl -sS -o /dev/null -w "%{http_code} %{time_total} bub\n" "http://localhost:5002/" || true
    fi
    sleep 0.1
  done
}

trap 'kill "${pids[@]}" 2>/dev/null || true' INT TERM EXIT

for i in $(seq 1 $CONCURRENCY); do
  worker &
  pids+=("$!")
done

wait
echo "Load test completed"


