#!/usr/bin/env bash
# platform.sh — Single entry-point for the entire Federated Commerce Platform.
#
# Commands:
#   install          Fresh install of both BUs (wipe volumes, install, split catalogue)
#   start            Start BUs + Federation services + Monitoring  [default]
#   stop             Stop all containers gracefully
#   restart          stop + start
#   teardown         Remove containers + networks (volumes preserved)
#   status           Full health check (BUs, Federation, Monitoring)
#   split            Re-apply category-based catalogue split to both BUs
#   outbox           Show latest outbox rows and backlog counts
#   outbox-watch     Poll outbox tables repeatedly to spot new rows / retries
#   kafka-peek       Show recent Kafka events without committing offsets
#   demo-degrade     Pause BU-A DB then run load test (demo: degraded BU scenario)
#
# Flags (can be combined):
#   --no-monitoring      Skip Prometheus / Grafana / Blackbox
#   --no-federation      Skip Federation services (Kafka, Keycloak, Relay, Indexer, Discovery)
#   --no-build           Skip Docker image rebuilds
#   --federation-only    Start Federation + Monitoring only (BUs assumed already up)
#   --skip-keycloak-plugin  Skip Keycloak plugin preparation step
#
# Examples:
#   ./platform.sh                      # start everything
#   ./platform.sh start --no-monitoring
#   ./platform.sh stop
#   ./platform.sh status
#   ./platform.sh install
#   ./platform.sh outbox bu-b 20       # latest 20 BU-B outbox rows
#   ./platform.sh kafka-peek federation.products 10
#   ./platform.sh demo-degrade 30 50   # 30s duration, 50 concurrency
#
# Credentials are read from .env (auto-sourced if present).
# Override any variable by exporting it before running the script.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# ── Load .env ────────────────────────────────────────────────────────────────
if [[ -f ".env" ]]; then
  # shellcheck disable=SC1091
  set -a; source ".env"; set +a
fi

BUA_DB_PASS=${BUA_DB_PASS:-"nopcommerce123"}
BUA_ADMIN_PASS=${BUA_ADMIN_PASS:-"BuA@Admin123!"}
BUB_DB_PASS=${BUB_DB_PASS:-"nopcommerce123"}
BUB_ADMIN_PASS=${BUB_ADMIN_PASS:-"BuB@Admin123!"}
KEYCLOAK_READY_TIMEOUT=${KEYCLOAK_READY_TIMEOUT:-120}

# ── Parse args ───────────────────────────────────────────────────────────────
COMMAND=${1:-"start"}
shift 2>/dev/null || shift 1 2>/dev/null || true

WITH_BUS=true
WITH_FEDERATION=true
WITH_MONITORING=true
BUILD_IMAGES=true
PREPARE_KEYCLOAK_PLUGIN=true

for arg in "$@"; do
  case "$arg" in
    --no-monitoring)         WITH_MONITORING=false ;;
    --no-federation)         WITH_FEDERATION=false ;;
    --no-build)              BUILD_IMAGES=false ;;
    --federation-only)       WITH_BUS=false ;;
    --skip-keycloak-plugin)  PREPARE_KEYCLOAK_PLUGIN=false ;;
  esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
BOLD=$'\033[1m'; RESET=$'\033[0m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'

log()    { echo "  $*"; }
header() { echo ""; echo "${BOLD}════════════════════════════════════════════════════════════════════${RESET}"; echo "  ${BOLD}$*${RESET}"; echo "${BOLD}════════════════════════════════════════════════════════════════════${RESET}"; }
ok()     { echo "  ${GREEN}✅  $*${RESET}"; }
warn()   { echo "  ${YELLOW}⚠️   $*${RESET}"; }
fail()   { echo "  ${RED}❌  $*${RESET}"; exit 1; }

http_code() { curl -s -o /dev/null -w "%{http_code}" "$1" 2>/dev/null || echo "000"; }
is_positive_integer() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }

require_running_container() {
  local ctr="$1" label="${2:-$1}"
  docker inspect -f '{{.State.Running}}' "$ctr" >/dev/null 2>&1 || fail "${label} container is not running"
}

print_outbox_snapshot() {
  local label="$1" ctr="$2" db_user="$3" limit="$4"
  echo ""
  echo "── ${label} Outbox ─────────────────────────────────────────────────────────────"
  docker exec "$ctr" psql -U "$db_user" -d nopcommerce -P pager=off -c '
SELECT
  COUNT(*)                                              AS total,
  COUNT(*) FILTER (WHERE "ProcessedOnUtc" IS NULL)     AS pending,
  COUNT(*) FILTER (WHERE "ProcessedOnUtc" IS NOT NULL) AS processed,
  COUNT(*) FILTER (WHERE "Attempts" >= 5)              AS deadletter,
  COALESCE(MAX("CreatedOnUtc"), NULL)                  AS newest_row_utc
FROM "OutboxMessage";'

  docker exec "$ctr" psql -U "$db_user" -d nopcommerce -P pager=off -c "
SELECT
  \"Id\",
  \"CreatedOnUtc\",
  \"EventType\",
  \"EntityId\",
  \"Topic\",
  \"ProcessedOnUtc\",
  \"Attempts\",
  LEFT(COALESCE(\"LastError\", ''), 120) AS \"LastError\"
FROM \"OutboxMessage\"
ORDER BY \"CreatedOnUtc\" DESC
LIMIT ${limit};"
}

run_outbox_command() {
  local scope="${1:-all}"
  local limit="${2:-10}"

  is_positive_integer "$limit" || fail "Outbox limit must be a positive integer"

  case "$scope" in
    bu-a|a)
      require_running_container nopcommerce_bua_postgres "BU-A postgres"
      print_outbox_snapshot "BU-A" nopcommerce_bua_postgres nopcommerce_bua "$limit"
      ;;
    bu-b|b)
      require_running_container nopcommerce_bub_postgres "BU-B postgres"
      print_outbox_snapshot "BU-B" nopcommerce_bub_postgres nopcommerce_bub "$limit"
      ;;
    all)
      require_running_container nopcommerce_bua_postgres "BU-A postgres"
      require_running_container nopcommerce_bub_postgres "BU-B postgres"
      print_outbox_snapshot "BU-A" nopcommerce_bua_postgres nopcommerce_bua "$limit"
      print_outbox_snapshot "BU-B" nopcommerce_bub_postgres nopcommerce_bub "$limit"
      ;;
    *)
      fail "Unknown outbox scope '${scope}' (use: bu-a, bu-b, or all)"
      ;;
  esac
}

run_outbox_watch_command() {
  local scope="${1:-all}"
  local limit="${2:-10}"
  local interval="${3:-2}"

  is_positive_integer "$limit" || fail "Outbox limit must be a positive integer"
  is_positive_integer "$interval" || fail "Outbox watch interval must be a positive integer"

  header "👀  Watching outbox updates (${scope}, limit=${limit}, interval=${interval}s)"
  while true; do
    command -v clear >/dev/null 2>&1 && clear
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Press Ctrl+C to stop."
    run_outbox_command "$scope" "$limit"
    sleep "$interval"
  done
}

run_kafka_peek_command() {
  local topic="${1:-federation.products}"
  local limit="${2:-10}"

  is_positive_integer "$limit" || fail "Kafka peek limit must be a positive integer"
  require_running_container federation_kafka "Kafka broker"

  header "🛰  Kafka peek (${topic}, last ${limit} message(s) per partition)"
  docker exec -e TOPIC="$topic" -e LIMIT="$limit" federation_kafka bash -lc '
set -euo pipefail
KAFKA_BIN=/opt/kafka/bin
offset_lines="$($KAFKA_BIN/kafka-get-offsets.sh --bootstrap-server localhost:9092 --topic "$TOPIC" 2>/dev/null || true)"

if [[ -z "$offset_lines" ]]; then
  echo "Topic not found or has no partitions: $TOPIC"
  exit 0
fi

while IFS=: read -r topic_name partition end_offset; do
  [[ -n "${topic_name:-}" ]] || continue
  [[ -n "${partition:-}" ]] || continue
  [[ -n "${end_offset:-}" ]] || continue

  start_offset=$(( end_offset > LIMIT ? end_offset - LIMIT : 0 ))
  message_count=$(( end_offset - start_offset ))

  echo
  echo "Partition $partition | end offset: $end_offset | showing: $message_count | start offset: $start_offset"
  if (( message_count == 0 )); then
    echo "  (no messages available)"
    continue
  fi

  "$KAFKA_BIN"/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic "$TOPIC" \
    --partition "$partition" \
    --offset "$start_offset" \
    --max-messages "$message_count" \
    --property print.timestamp=true \
    --property print.partition=true \
    --property print.offset=true \
    --property print.key=true \
    --property print.headers=true \
    --consumer-property enable.auto.commit=false
done <<< "$offset_lines"

echo
echo "Peek completed without committing consumer offsets."
'
}

# ── BU helpers ───────────────────────────────────────────────────────────────
bus_up() {
  local extra="${1:-}"
  if [[ "$BUILD_IMAGES" == "true" ]]; then
    BUA_DB_PASS="${BUA_DB_PASS}" BUA_ADMIN_PASS="${BUA_ADMIN_PASS}" \
      docker compose -f docker-compose.bua.yml up -d --build postgres-bua nopcommerce-bua
    BUB_DB_PASS="${BUB_DB_PASS}" BUB_ADMIN_PASS="${BUB_ADMIN_PASS}" \
      docker compose -f docker-compose.bub.yml up -d --build postgres-bub nopcommerce-bub
  else
    BUA_DB_PASS="${BUA_DB_PASS}" BUA_ADMIN_PASS="${BUA_ADMIN_PASS}" \
      docker compose -f docker-compose.bua.yml up -d postgres-bua nopcommerce-bua
    BUB_DB_PASS="${BUB_DB_PASS}" BUB_ADMIN_PASS="${BUB_ADMIN_PASS}" \
      docker compose -f docker-compose.bub.yml up -d postgres-bub nopcommerce-bub
  fi
}

buses_stop() {
  BUA_DB_PASS="${BUA_DB_PASS}" BUA_ADMIN_PASS="${BUA_ADMIN_PASS}" \
    docker compose -f docker-compose.bua.yml stop || true
  BUB_DB_PASS="${BUB_DB_PASS}" BUB_ADMIN_PASS="${BUB_ADMIN_PASS}" \
    docker compose -f docker-compose.bub.yml stop || true
}

buses_down() {
  BUA_DB_PASS="${BUA_DB_PASS}" BUA_ADMIN_PASS="${BUA_ADMIN_PASS}" \
    docker compose -f docker-compose.bua.yml down || true
  BUB_DB_PASS="${BUB_DB_PASS}" BUB_ADMIN_PASS="${BUB_ADMIN_PASS}" \
    docker compose -f docker-compose.bub.yml down || true
}

run_split() {
  local bu=$1 compose_file=$2 postgres_svc=$3 db_user=$4
  log "[split] Running catalogue split for ${bu}..."
  SPLIT_ROLE="${bu}" COMPOSE_FILE="${PROJECT_ROOT}/${compose_file}" \
  POSTGRES_SERVICE="${postgres_svc}" DB_USER="${db_user}" DB_NAME="nopcommerce" \
    "${PROJECT_ROOT}/scripts/data/split-by-category.sh"
}

# ── Keycloak / plugin helpers ────────────────────────────────────────────────
ensure_plugins_json_contains_keycloak() {
  local file="$1"
  python3 - "$file" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8-sig"))
plugins = data.setdefault("Plugins", [])
if not any(p.get("SystemName") == "ExternalAuth.Keycloak" for p in plugins):
    plugins.append({"SystemName": "ExternalAuth.Keycloak", "Version": "1.0.0"})
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
}

ensure_keycloak_plugin_in_container() {
  local c="$1"
  docker exec "$c" sh -c '
    test -f /app/Plugins/ExternalAuth.Keycloak/Nop.Plugin.ExternalAuth.Keycloak.dll &&
    test -f /app/Plugins/ExternalAuth.Keycloak/plugin.json &&
    test -f /app/Plugins/ExternalAuth.Keycloak/Views/PublicInfo.cshtml
  '
}

activate_keycloak_in_db() {
  local ctr="$1" usr="$2"
  docker exec "$ctr" psql -U "$usr" -d nopcommerce -c "
UPDATE \"Setting\" SET \"Value\" = CASE
  WHEN COALESCE(\"Value\",'') = '' THEN 'ExternalAuth.Keycloak'
  WHEN POSITION('ExternalAuth.Keycloak' IN \"Value\") > 0 THEN \"Value\"
  ELSE \"Value\" || ',ExternalAuth.Keycloak'
END WHERE \"Name\" = 'externalauthenticationsettings.activeauthenticationmethodsystemnames';" >/dev/null
}

seed_keycloak_in_db() {
  local ctr="$1" usr="$2" cid="$3" csec="$4"
  docker exec "$ctr" psql -U "$usr" -d nopcommerce -c "
WITH seed(\"Name\",\"Value\",\"StoreId\") AS (VALUES
  ('keycloakauthenticationsettings.authority','http://localhost:8080/realms/nop-federation',0),
  ('keycloakauthenticationsettings.metadataaddress','http://keycloak:8080/realms/nop-federation/.well-known/openid-configuration',0),
  ('keycloakauthenticationsettings.validissuer','http://localhost:8080/realms/nop-federation',0),
  ('keycloakauthenticationsettings.clientid','$cid',0),
  ('keycloakauthenticationsettings.clientsecret','$csec',0)),
updated AS (UPDATE \"Setting\" s SET \"Value\"=seed.\"Value\" FROM seed
  WHERE s.\"Name\"=seed.\"Name\" AND s.\"StoreId\"=seed.\"StoreId\" RETURNING s.\"Name\",s.\"StoreId\")
INSERT INTO \"Setting\"(\"Name\",\"Value\",\"StoreId\")
SELECT seed.\"Name\",seed.\"Value\",seed.\"StoreId\" FROM seed
LEFT JOIN updated u ON u.\"Name\"=seed.\"Name\" AND u.\"StoreId\"=seed.\"StoreId\"
WHERE u.\"Name\" IS NULL;" >/dev/null
}

prepare_keycloak_plugin() {
  log "Preparing Keycloak plugin in BU containers..."
  ensure_plugins_json_contains_keycloak "${PROJECT_ROOT}/_appdata-bua/plugins.json"
  ensure_plugins_json_contains_keycloak "${PROJECT_ROOT}/_appdata-bub/plugins.json"
  if ! ensure_keycloak_plugin_in_container nopcommerce_bua_web || \
     ! ensure_keycloak_plugin_in_container nopcommerce_bub_web; then
    if [[ "$BUILD_IMAGES" == "true" ]]; then
      log "Rebuilding BU images to bake in Keycloak plugin..."
      BUA_DB_PASS="${BUA_DB_PASS}" BUA_ADMIN_PASS="${BUA_ADMIN_PASS}" \
        docker compose -f docker-compose.bua.yml up -d --build postgres-bua nopcommerce-bua >/dev/null
      BUB_DB_PASS="${BUB_DB_PASS}" BUB_ADMIN_PASS="${BUB_ADMIN_PASS}" \
        docker compose -f docker-compose.bub.yml up -d --build postgres-bub nopcommerce-bub >/dev/null
    else
      fail "Keycloak plugin missing from BU images. Re-run without --no-build."
    fi
  fi
  ensure_keycloak_plugin_in_container nopcommerce_bua_web || fail "Keycloak plugin missing in BU-A after rebuild"
  ensure_keycloak_plugin_in_container nopcommerce_bub_web || fail "Keycloak plugin missing in BU-B after rebuild"
  activate_keycloak_in_db nopcommerce_bua_postgres nopcommerce_bua
  activate_keycloak_in_db nopcommerce_bub_postgres nopcommerce_bub
  seed_keycloak_in_db nopcommerce_bua_postgres nopcommerce_bua "bu-a-client" "bu-a-secret"
  seed_keycloak_in_db nopcommerce_bub_postgres nopcommerce_bub "bu-b-client" "bu-b-secret"
  docker restart nopcommerce_bua_web nopcommerce_bub_web >/dev/null
  ok "Keycloak plugin configured and BU web containers restarted"
}

# ── Keycloak readiness ───────────────────────────────────────────────────────
wait_for_keycloak() {
  local timeout=$KEYCLOAK_READY_TIMEOUT elapsed=0 interval=5
  local oidc_url="http://localhost:8080/realms/nop-federation/.well-known/openid-configuration"
  log "Waiting for Keycloak OIDC readiness (timeout: ${timeout}s)..."
  while true; do
    [[ "$(http_code "$oidc_url")" == "200" ]] && ok "Keycloak ready (${elapsed}s)" && return 0
    (( elapsed >= timeout )) && fail "Keycloak did not become ready within ${timeout}s"
    sleep "$interval"; elapsed=$(( elapsed + interval ))
    log "  … waiting (${elapsed}s / ${timeout}s)"
  done
}

# ── Network setup ────────────────────────────────────────────────────────────
network_setup() {
  docker network create federation-net 2>/dev/null && ok "federation-net created" || log "federation-net already exists"
  for alias_ctr in "postgres-bua:nopcommerce_bua_postgres" "postgres-bub:nopcommerce_bub_postgres"; do
    alias=${alias_ctr%%:*}; ctr=${alias_ctr#*:}
    docker network connect --alias "$alias" federation-net "$ctr" 2>/dev/null \
      && ok "${alias} connected" || log "${alias} already connected"
  done
  for ctr in nopcommerce_bua_web nopcommerce_bub_web; do
    docker network connect federation-net "$ctr" 2>/dev/null \
      && ok "$ctr connected" || log "$ctr already connected"
  done
  docker exec nopcommerce_bua_postgres psql -U nopcommerce_bua -d nopcommerce \
    -c "CREATE SCHEMA IF NOT EXISTS keycloak;" 2>/dev/null \
    && ok "keycloak schema ready" || warn "Could not create keycloak schema (postgres-bua not running yet?)"
}

# ── Print status summary ─────────────────────────────────────────────────────
print_endpoints() {
  echo ""
  echo "  BU-A Storefront:     http://localhost:5001"
  echo "  BU-B Storefront:     http://localhost:5002"
  echo ""
  echo "  Keycloak admin:      http://localhost:8080  (admin/admin)"
  echo "  Meilisearch:         http://localhost:7700"
  echo "  Discovery API:       http://localhost:5010/api/search?q=*"
  echo "  Discovery Web:       http://localhost:5011"
  echo ""
  echo "  Prometheus:          http://localhost:9090"
  echo "  Grafana:             http://localhost:3000  (admin/admin)"
  echo ""
  echo "  SSO login (BU-A):    http://localhost:5001/keycloakauthentication/login"
  echo "  SSO login (BU-B):    http://localhost:5002/keycloakauthentication/login"
  echo ""
  echo "  Check status:        ./platform.sh status"
  echo "  Stop everything:     ./platform.sh stop"
  echo ""
}

# ═════════════════════════════════════════════════════════════════════════════
# COMMANDS
# ═════════════════════════════════════════════════════════════════════════════

case "$COMMAND" in

  # ── install ────────────────────────────────────────────────────────────────
  install)
    header "📦  Fresh install of both Business Units"

    # Build the shared nopCommerce image ONCE — both BUs run identical binaries.
    # This avoids the Docker daemon receiving a 1.4 GB context twice and
    # compiling the same .NET code twice.
    log "── Pre-building shared nopCommerce image (once for both BUs) ─────────"
    docker build -t nop-nopcommerce:latest -f Presentation/Nop.Web/Dockerfile .
    ok "Shared nopCommerce image ready"

    # Build the tiny auto-install helper once too (Alpine + curl, ~8 MB).
    log "── Pre-building shared auto-install image ────────────────────────────"
    docker build -t nop-auto-install:latest \
      -f scripts/bootstrap/auto-install.Dockerfile scripts/bootstrap
    ok "Shared auto-install image ready"

    echo ""
    # BU-A: image already built — skip rebuild, keep auto-install image for BU-B
    BU=a BUA_DB_PASS="${BUA_DB_PASS}" BUA_ADMIN_PASS="${BUA_ADMIN_PASS}" \
    BUILD_NOP_IMAGE=false CLEAN_IMAGES=false SEED_PRODUCTS=northstar SPLIT_ROLE=bu-a \
      "${PROJECT_ROOT}/scripts/bootstrap/reset-and-install-bu.sh"
    echo ""
    # BU-B: reuses the same pre-built images
    BU=b BUB_DB_PASS="${BUB_DB_PASS}" BUB_ADMIN_PASS="${BUB_ADMIN_PASS}" \
    BUILD_NOP_IMAGE=false CLEAN_IMAGES=true SEED_PRODUCTS=northstar SPLIT_ROLE=bu-b \
      "${PROJECT_ROOT}/scripts/bootstrap/reset-and-install-bu.sh"
    ok "Both BUs installed and catalogues split"
    echo "  BU-A → http://localhost:5001   BU-B → http://localhost:5002"
    ;;

  # ── start ─────────────────────────────────────────────────────────────────
  start)
    header "🚀  Starting Federated Commerce Platform"

    if [[ "$WITH_BUS" == "true" ]]; then
      log "── Step 1/4: Starting BU-A + BU-B ──────────────────────────────────────"
      bus_up
      ok "BU-A and BU-B containers started"
      log "Giving nopCommerce 15s to initialise..."
      sleep 15
    else
      log "── Step 1/4: BUs skipped (--federation-only) ────────────────────────────"
    fi

    if [[ "$WITH_FEDERATION" == "true" ]]; then
      log "── Step 2/4: Network setup ──────────────────────────────────────────────"
      network_setup

      if [[ "$PREPARE_KEYCLOAK_PLUGIN" == "true" ]]; then
        log "── Step 2.5/4: Keycloak plugin preparation ──────────────────────────────"
        prepare_keycloak_plugin
      fi

      log "── Step 3/4: Starting Keycloak ──────────────────────────────────────────"
      if [[ "$BUILD_IMAGES" == "true" ]]; then
        docker compose -f docker-compose.federation.yml up -d --build keycloak
      else
        docker compose -f docker-compose.federation.yml up -d keycloak
      fi
      wait_for_keycloak

      log "── Step 4/4: Starting Federation services ───────────────────────────────"
      if [[ "$BUILD_IMAGES" == "true" ]]; then
        docker compose -f docker-compose.federation.yml up -d --build \
          kafka meilisearch kafka-relay meili-indexer discovery-api discovery-web
      else
        docker compose -f docker-compose.federation.yml up -d \
          kafka meilisearch kafka-relay meili-indexer discovery-api discovery-web
      fi
      ok "Federation services started"
    else
      log "── Federation services skipped (--no-federation) ────────────────────────"
    fi

    if [[ "$WITH_MONITORING" == "true" ]]; then
      log "── Monitoring: Starting Prometheus + Grafana + Blackbox ─────────────────"
      docker compose -f monitoring/docker-compose.prometheus.yml up -d \
        || warn "Monitoring stack failed to start (non-fatal)"
      ok "Monitoring started (Prometheus: http://localhost:9090, Grafana: http://localhost:3000)"
    fi

    header "✅  Platform is UP"
    print_endpoints
    ;;

  # ── stop ──────────────────────────────────────────────────────────────────
  stop)
    header "⏹  Stopping everything"
    docker compose -f docker-compose.federation.yml stop || true
    buses_stop
    if [[ "$WITH_MONITORING" == "true" ]]; then
      docker compose -f monitoring/docker-compose.prometheus.yml stop || true
    fi
    ok "All services stopped (containers + volumes preserved — run 'start' to resume)"
    ;;

  # ── restart ───────────────────────────────────────────────────────────────
  restart)
    "$0" stop "$@"
    sleep 3
    "$0" start "$@"
    ;;

  # ── teardown ──────────────────────────────────────────────────────────────
  teardown)
    header "🗑  Tearing down all containers"
    docker compose -f docker-compose.federation.yml down || true
    buses_down
    if [[ "$WITH_MONITORING" == "true" ]]; then
      docker compose -f monitoring/docker-compose.prometheus.yml down || true
    fi
    ok "All containers and networks removed (volumes preserved)"
    ;;

  # ── status ────────────────────────────────────────────────────────────────
  status)
    header "📊  Platform Status"

    echo ""
    echo "── BU-A ─────────────────────────────────────────────────────────────────"
    BUA_DB_PASS="${BUA_DB_PASS}" BUA_ADMIN_PASS="${BUA_ADMIN_PASS}" \
      docker compose -f docker-compose.bua.yml ps 2>/dev/null || echo "  Not running"
    code=$(http_code "http://localhost:5001/"); [[ "$code" == "200" ]] && ok "HTTP $code" || warn "HTTP $code"

    echo ""
    echo "── BU-B ─────────────────────────────────────────────────────────────────"
    BUB_DB_PASS="${BUB_DB_PASS}" BUB_ADMIN_PASS="${BUB_ADMIN_PASS}" \
      docker compose -f docker-compose.bub.yml ps 2>/dev/null || echo "  Not running"
    code=$(http_code "http://localhost:5002/"); [[ "$code" == "200" ]] && ok "HTTP $code" || warn "HTTP $code"

    echo ""
    echo "── Federation Platform ──────────────────────────────────────────────────"
    docker compose -f docker-compose.federation.yml ps 2>/dev/null || echo "  Not running"
    for label_url in \
      "Keycloak OIDC|http://localhost:8080/realms/nop-federation/.well-known/openid-configuration" \
      "Meilisearch|http://localhost:7700/health" \
      "Discovery API|http://localhost:5010/health" \
      "Discovery Web|http://localhost:5011"; do
      label=${label_url%%|*}; url=${label_url#*|}
      code=$(http_code "$url")
      [[ "$code" =~ ^2 ]] && ok "${label}: HTTP ${code}" || warn "${label}: HTTP ${code}"
    done

    echo ""
    echo "── SSO spot-checks ──────────────────────────────────────────────────────"
    for bu_url in "BU-A SSO|http://localhost:5001/keycloakauthentication/login" \
                  "BU-B SSO|http://localhost:5002/keycloakauthentication/login"; do
      label=${bu_url%%|*}; url=${bu_url#*|}
      code=$(http_code "$url")
      [[ "$code" == "302" ]] && ok "${label}: HTTP $code" || warn "${label}: HTTP $code"
    done

    echo ""
    echo "── Monitoring ───────────────────────────────────────────────────────────"
    docker compose -f monitoring/docker-compose.prometheus.yml ps 2>/dev/null || echo "  Not running"
    code=$(http_code "http://localhost:9090/"); [[ "$code" =~ ^[23] ]] && ok "Prometheus: HTTP $code" || warn "Prometheus: HTTP $code"
    code=$(http_code "http://localhost:3000/"); [[ "$code" =~ ^[23] ]] && ok "Grafana: HTTP $code" || warn "Grafana: HTTP $code"

    echo ""
    ;;

  # ── split ─────────────────────────────────────────────────────────────────
  split)
    header "🔀  Applying category-based catalogue split"
    run_split "bu-a" "docker-compose.bua.yml" "postgres-bua" "nopcommerce_bua"
    run_split "bu-b" "docker-compose.bub.yml" "postgres-bub" "nopcommerce_bub"
    ok "Catalogue split applied"
    ;;

  # ── outbox ────────────────────────────────────────────────────────────────
  outbox)
    header "📬  Outbox snapshot"
    run_outbox_command "${1:-all}" "${2:-10}"
    ;;

  # ── outbox-watch ──────────────────────────────────────────────────────────
  outbox-watch)
    run_outbox_watch_command "${1:-all}" "${2:-10}" "${3:-2}"
    ;;

  # ── kafka-peek ────────────────────────────────────────────────────────────
  kafka-peek)
    run_kafka_peek_command "${1:-federation.products}" "${2:-10}"
    ;;


  # ── demo-degrade ──────────────────────────────────────────────────────────
  demo-degrade)
    DURATION=${1:-30}
    CONCURRENCY=${2:-50}
    header "🎭  Demo: BU-A degradation scenario (${DURATION}s, ${CONCURRENCY} workers)"
    if [[ -x "${PROJECT_ROOT}/scripts/demo/simulate_degradation.sh" ]]; then
      "${PROJECT_ROOT}/scripts/demo/simulate_degradation.sh" "$CONCURRENCY" "$DURATION"
    else
      fail "scripts/demo/simulate_degradation.sh not found or not executable"
    fi
    ;;

  # ── legacy aliases ────────────────────────────────────────────────────────
  federation-up)   "$0" start --federation-only "$@" ;;
  federation-down) "$0" stop "$@" ;;
  phase2-up)       "$0" start --federation-only "$@" ;;
  phase2-down)     "$0" stop "$@" ;;
  up)              "$0" start "$@" ;;
  down)            "$0" stop "$@" ;;

  # ── help ──────────────────────────────────────────────────────────────────
  help|--help|-h)
    echo ""
    echo "${BOLD}Federated Commerce Platform — unified CLI${RESET}"
    echo ""
    echo "  ${BOLD}./platform.sh <command> [flags]${RESET}"
    echo ""
    echo "Commands:"
    echo "  install          Fresh install: wipe volumes, install BUs, apply catalogue split"
    echo "  start            Start everything: BUs + Federation + Monitoring  [default]"
    echo "  stop             Stop all containers gracefully (volumes kept)"
    echo "  restart          stop + start"
    echo "  teardown         Remove all containers + networks (volumes kept)"
    echo "  status           Full health check for every component"
    echo "  split            Re-apply category-based catalogue split"
    echo "  outbox           Show latest outbox rows [bu-a|bu-b|all] [limit]"
    echo "  outbox-watch     Poll outbox tables [bu-a|bu-b|all] [limit] [interval_s]"
    echo "  kafka-peek       Show recent Kafka events [topic] [limit_per_partition]"
    echo "  demo-degrade     BU-A degradation demo [duration_s] [concurrency]"
    echo ""
    echo "Flags:"
    echo "  --no-monitoring       Exclude Prometheus / Grafana / Blackbox"
    echo "  --no-federation       Exclude Federation services"
    echo "  --federation-only     Skip BUs (assume already running)"
    echo "  --no-build            Skip Docker image rebuilds"
    echo "  --skip-keycloak-plugin  Skip Keycloak plugin preparation"
    echo ""
    echo "Credentials via .env or exported environment variables:"
    echo "  BUA_DB_PASS / BUA_ADMIN_PASS   BUB_DB_PASS / BUB_ADMIN_PASS"
    echo "  KEYCLOAK_READY_TIMEOUT (default: 120s)"
    echo ""
    ;;

  *)
    echo "Unknown command: $COMMAND"
    "$0" --help
    exit 1
    ;;
esac


