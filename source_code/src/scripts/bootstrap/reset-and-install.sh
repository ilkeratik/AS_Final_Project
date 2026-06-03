#!/usr/bin/env bash
# scripts/bootstrap/reset-and-install.sh
# Idempotent helper to reset App_Data, run the auto-install one-shot, and clean temporary artifacts.
# Usage:
#   REMOVE_VOLUMES=true CLEAN_IMAGES=true ./scripts/bootstrap/reset-and-install.sh
set -euo pipefail

PROJECT_ROOT=${PROJECT_ROOT:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"}
COMPOSE_FILE=${COMPOSE_FILE:-"${PROJECT_ROOT}/docker-compose.bua.yml"}
APPDATA_HOST_DIR=${APPDATA_HOST_DIR:-"${PROJECT_ROOT}/_appdata"}
APPDATA_CONTAINER_PATH=${APPDATA_CONTAINER_PATH:-"/app/App_Data"}
TEMPLATE_APPSETTINGS=${TEMPLATE_APPSETTINGS:-"${PROJECT_ROOT}/Presentation/Nop.Web/App_Data/appsettings.json"}
RESET_APPSETTINGS=${RESET_APPSETTINGS:-"true"}
REMOVE_VOLUMES=${REMOVE_VOLUMES:-"false"}        # set true to remove docker volumes (data loss)
CLEAN_IMAGES=${CLEAN_IMAGES:-"false"}            # set true to remove built auto-install images after run
SPLIT_AFTER_INSTALL=${SPLIT_AFTER_INSTALL:-"false"} # set true to run split-by-category (legacy)
SPLIT_ROLE=${SPLIT_ROLE:-"bu-a"}                 # bu-a|bu-b
SEED_PRODUCTS=${SEED_PRODUCTS:-"northstar"}       # northstar|split|none  — controls post-install catalogue
WAIT_SECONDS=${WAIT_SECONDS:-300}
SLEEP=1
BUILD_NOP_IMAGE=${BUILD_NOP_IMAGE:-true}  # set false to skip --build (use pre-built nop-nopcommerce:latest)

# -- Service / container name overrides ---------------------------------------
# Override these when using a BU-specific compose file (e.g. docker-compose.bua.yml)
# so that all docker compose exec / docker inspect calls target the right container.
POSTGRES_SERVICE=${POSTGRES_SERVICE:-"postgres"}          # compose service name for postgres
NOP_SERVICE=${NOP_SERVICE:-"nopcommerce"}                 # compose service name for nopcommerce web
NOP_WEB_CONTAINER=${NOP_WEB_CONTAINER:-"nopcommerce_web"} # actual container_name for health checks
INSTALL_SERVICE=${INSTALL_SERVICE:-"nopcommerce-auto-install"} # compose service name for installer
INSTALL_CONTAINER_FILTER=${INSTALL_CONTAINER_FILTER:-"nopcommerce_auto_install"} # docker ps filter

echo "[reset-and-install] Using compose file: ${COMPOSE_FILE}"

# 1) Optionally stop services and remove containers
echo "[reset-and-install] Bringing down compose (containers only)"
docker compose -f "${COMPOSE_FILE}" down || true

# 2) Optionally remove volumes
if [ "${REMOVE_VOLUMES}" = "true" ]; then
  echo "[reset-and-install] Removing compose volumes (WARNING: destructive)"
  docker compose -f "${COMPOSE_FILE}" down -v || true
  # External volumes are not removed by 'down -v'; remove them explicitly.
  # Derive the volume names from the BU label (bu-a → bua, bu-b → bub).
  BU_SUFFIX=$(echo "${SPLIT_ROLE:-bu-a}" | tr -d '-')   # bu-a→bua, bu-b→bub
  for VOL in "src_postgres-data-${BU_SUFFIX}" "src_wwwroot-thumbs-${BU_SUFFIX}" "src_wwwroot-uploaded-${BU_SUFFIX}"; do
    if docker volume inspect "${VOL}" >/dev/null 2>&1; then
      echo "[reset-and-install] Removing external volume: ${VOL}"
      docker volume rm "${VOL}" || true
    fi
  done
  
  # Recreate external volumes so Docker Compose can find them
  echo "[reset-and-install] Recreating external volumes"
  for VOL in "src_postgres-data-${BU_SUFFIX}" "src_wwwroot-thumbs-${BU_SUFFIX}" "src_wwwroot-uploaded-${BU_SUFFIX}"; do
    echo "[reset-and-install] Creating volume: ${VOL}"
    docker volume create "${VOL}"
  done
fi

# 3) Ensure host App_Data dir exists and restore template appsettings
if [ "${RESET_APPSETTINGS}" = "true" ]; then
  echo "[reset-and-install] Resetting host App_Data appsettings.json"
  mkdir -p "${APPDATA_HOST_DIR}"
  if [ -f "${TEMPLATE_APPSETTINGS}" ]; then
    cp "${TEMPLATE_APPSETTINGS}" "${APPDATA_HOST_DIR}/appsettings.json"
    echo "[reset-and-install] Copied template appsettings from ${TEMPLATE_APPSETTINGS}"
  else
    cat > "${APPDATA_HOST_DIR}/appsettings.json" <<'JSON'
{
  "ConnectionStrings": {
    "ConnectionString": null,
    "DataProvider": "postgresql",
    "SQLCommandTimeout": null,
    "WithNoLock": false,
    "Collation": "",
    "CharacterSet": ""
  }
}
JSON
    echo "[reset-and-install] Wrote minimal appsettings.json template"
  fi
fi

# 4) Start only DB + web to let the site boot
echo "[reset-and-install] Starting ${POSTGRES_SERVICE} and ${NOP_SERVICE}"
if [ "${BUILD_NOP_IMAGE}" = "true" ]; then
  # Build the web image so the running container always reflects current source code.
  docker compose -f "${COMPOSE_FILE}" up -d --build "${POSTGRES_SERVICE}" "${NOP_SERVICE}"
else
  # Shared nop-nopcommerce:latest was pre-built — skip rebuild to avoid redundant compile.
  echo "[reset-and-install] BUILD_NOP_IMAGE=false — using pre-built nop-nopcommerce:latest"
  docker compose -f "${COMPOSE_FILE}" up -d "${POSTGRES_SERVICE}" "${NOP_SERVICE}"
fi

# 5) Wait for nopcommerce /install to respond
NOP_URL=${NOP_URL:-"http://localhost:5001"}
echo "[reset-and-install] Waiting up to ${WAIT_SECONDS}s for ${NOP_URL}/install"
i=0
HTTP_CODE=000
while [ "$i" -lt "$WAIT_SECONDS" ]; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${NOP_URL}/install" || echo "000")
  # Only HTTP 200 means the install page rendered correctly and we can proceed.
  if [ "$HTTP_CODE" = "200" ]; then
    echo "[reset-and-install] /install responded HTTP $HTTP_CODE"
    break
  fi
  i=$((i + SLEEP))
  sleep $SLEEP
done

if [ "$HTTP_CODE" != "200" ]; then
  echo "[reset-and-install] ERROR: /install did not return HTTP 200 after ${WAIT_SECONDS}s (last code: ${HTTP_CODE})"
  exit 1
fi

# 6) Build auto-install image and run it
echo "[reset-and-install] Building auto-install image"
docker compose -f "${COMPOSE_FILE}" build "${INSTALL_SERVICE}"

echo "[reset-and-install] Starting auto-install (one-shot)"
docker compose -f "${COMPOSE_FILE}" up -d "${INSTALL_SERVICE}"

# Wait for the auto-install container to exit (with timeout)
INSTALL_CONTAINER_NAME=$(docker ps -a --filter "name=${INSTALL_CONTAINER_FILTER}" --format "{{.ID}}")
if [ -z "${INSTALL_CONTAINER_NAME}" ]; then
  echo "[reset-and-install] ERROR: auto-install container not found (filter=name=${INSTALL_CONTAINER_FILTER})"
  exit 1
fi

echo "[reset-and-install] Waiting for auto-install container ${INSTALL_CONTAINER_NAME} to finish (timeout ${WAIT_SECONDS}s)"
i=0
while [ "$i" -lt "$WAIT_SECONDS" ]; do
  STATUS=$(docker inspect --format='{{.State.Status}} {{.State.ExitCode}}' "${INSTALL_CONTAINER_NAME}" 2>/dev/null || echo "notfound")
  if echo "$STATUS" | grep -q "exited"; then
    echo "[reset-and-install] auto-install finished: $STATUS"
    break
  fi
  sleep $SLEEP
  i=$((i + SLEEP))
done

# Show logs
echo "[reset-and-install] Auto-install logs:"
docker compose -f "${COMPOSE_FILE}" logs --tail=200 "${INSTALL_SERVICE}" || true

# 7) Remove the auto-install container
echo "[reset-and-install] Removing auto-install container"
docker compose -f "${COMPOSE_FILE}" rm -s -f "${INSTALL_SERVICE}" || true

# 8) Optionally remove auto-install images
if [ "${CLEAN_IMAGES}" = "true" ]; then
  echo "[reset-and-install] Cleaning auto-install images"
  docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | grep -i "auto-install" | awk '{print $2}' | xargs -r docker rmi -f || true
fi

# 9) Normalize public URLs so generated absolute links don't leak internal Docker hostnames
DB_USER_VAL=${DB_USER:-"nopcommerce"}
DB_NAME_VAL=${DB_NAME:-"nopcommerce"}
PUBLIC_URL="${NOP_URL%/}/"
echo "[reset-and-install] Normalizing store and sample-content URLs to ${PUBLIC_URL}"
docker compose -f "${COMPOSE_FILE}" exec -T "${POSTGRES_SERVICE}" psql -U "${DB_USER_VAL}" -d "${DB_NAME_VAL}" -v ON_ERROR_STOP=1 -c "
UPDATE \"Store\"
SET \"Url\" = '${PUBLIC_URL}'
WHERE \"Url\" IS DISTINCT FROM '${PUBLIC_URL}';

UPDATE \"Setting\"
SET \"Value\" = replace(replace(\"Value\", 'http://nopcommerce-bua/', '${PUBLIC_URL}'), 'http://nopcommerce-bub/', '${PUBLIC_URL}')
WHERE \"Name\" = 'swipersettings.slides'
  AND (\"Value\" LIKE '%nopcommerce-bua%' OR \"Value\" LIKE '%nopcommerce-bub%');
" </dev/null || true

echo "[reset-and-install] Restarting ${NOP_SERVICE} to clear cached settings"
docker compose -f "${COMPOSE_FILE}" restart "${NOP_SERVICE}" >/dev/null

# 10) Final check - verify installation is complete
echo "[reset-and-install] Verifying installation status..."
FINAL_INSTALL_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${NOP_URL}/install" || echo "000")
echo "[reset-and-install] Final /install HTTP code: ${FINAL_INSTALL_CODE}"

# Follow redirects to see where we end up
FINAL_CHECK_PAGE=$(mktemp)
trap 'rm -f "$FINAL_CHECK_PAGE"' EXIT
FINAL_URL=$(curl -sL -w "%{url_effective}" -o "$FINAL_CHECK_PAGE" "${NOP_URL}/install" || echo "")
echo "[reset-and-install] After following redirects, final URL: ${FINAL_URL}"

# Check if we're stuck in redirect loop to /install
case "$FINAL_URL" in
  *"/install"*)
    if [ "$FINAL_INSTALL_CODE" = "302" ] || [ "$FINAL_INSTALL_CODE" = "301" ]; then
      echo "[reset-and-install] WARNING: /install redirects but still ends at /install URL (possible redirect loop)"
      echo "[reset-and-install] This usually means the database isn't properly initialized or connection string is wrong"
    else
      echo "[reset-and-install] WARN: /install still returns ${FINAL_INSTALL_CODE} - install page still active"
    fi
    ;;
  *)
    echo "[reset-and-install] OK: /install redirects away to ${FINAL_URL} - likely installed"
    ;;
esac
rm -f "$FINAL_CHECK_PAGE"

# 11) Report DB seed status and VALIDATE
echo "[reset-and-install] Verifying DB seed (Store/Language counts):"
STORE_COUNT=$(docker compose -f "${COMPOSE_FILE}" exec -T "${POSTGRES_SERVICE}" psql -U "${DB_USER_VAL}" -d "${DB_NAME_VAL}" -tAc 'select count(*) from "Store";' </dev/null 2>/dev/null | tr -d '[:space:]' || echo "0")
LANGUAGE_COUNT=$(docker compose -f "${COMPOSE_FILE}" exec -T "${POSTGRES_SERVICE}" psql -U "${DB_USER_VAL}" -d "${DB_NAME_VAL}" -tAc 'select count(*) from "Language";' </dev/null 2>/dev/null | tr -d '[:space:]' || echo "0")

echo "[reset-and-install] Store count: ${STORE_COUNT}"
echo "[reset-and-install] Language count: ${LANGUAGE_COUNT}"

# Validate that installation actually created data
if [ "$STORE_COUNT" = "0" ]; then
  echo "[reset-and-install] ERROR: No stores found in database!"
  echo "[reset-and-install] Installation failed - database was created but not populated."
  echo "[reset-and-install] Check the auto-installer logs above for errors."
  exit 1
fi

if [ "$LANGUAGE_COUNT" = "0" ]; then
  echo "[reset-and-install] WARNING: No languages found in database (installation may be incomplete)"
fi

echo "[reset-and-install] ✓ Database validation passed - found ${STORE_COUNT} store(s) and ${LANGUAGE_COUNT} language(s)"

# 12) Post-install catalogue seeding
case "${SEED_PRODUCTS:-northstar}" in
  northstar)
    echo "[reset-and-install] Applying Northstar Living Group catalogue (ROLE=${SPLIT_ROLE})"
    BU="${SPLIT_ROLE}" \
      "${PROJECT_ROOT}/scripts/data/apply-northstar-seed.sh"
    ;;
  split)
    # Legacy: split nopCommerce sample products by category
    if [ "${SPLIT_AFTER_INSTALL}" = "true" ]; then
      echo "[reset-and-install] Splitting by category (ROLE=${SPLIT_ROLE})"
      SPLIT_ROLE="${SPLIT_ROLE}" COMPOSE_FILE="${COMPOSE_FILE}" \
      POSTGRES_SERVICE="${POSTGRES_SERVICE}" DB_USER="${DB_USER_VAL}" DB_NAME="${DB_NAME_VAL}" \
        "${PROJECT_ROOT}/scripts/data/split-by-category.sh"
    fi
    ;;
  none)
    echo "[reset-and-install] SEED_PRODUCTS=none — skipping catalogue seeding"
    ;;
esac

# 13) Apply BU-specific Federation Outbox settings and restart the site so the
# hosted product backfill sees the correct StoreCode / StoreName / Enabled values.
OUTBOX_SETTINGS_SQL=""
case "${SPLIT_ROLE}" in
  bu-a) OUTBOX_SETTINGS_SQL="${PROJECT_ROOT}/scripts/data/seed-outbox-settings-bua.sql" ;;
  bu-b) OUTBOX_SETTINGS_SQL="${PROJECT_ROOT}/scripts/data/seed-outbox-settings-bub.sql" ;;
esac

if [ -n "${OUTBOX_SETTINGS_SQL}" ] && [ -f "${OUTBOX_SETTINGS_SQL}" ]; then
  echo "[reset-and-install] Applying Federation Outbox settings from ${OUTBOX_SETTINGS_SQL}"
  docker compose -f "${COMPOSE_FILE}" exec -T "${POSTGRES_SERVICE}" \
    psql -U "${DB_USER_VAL}" -d "${DB_NAME_VAL}" -v ON_ERROR_STOP=1 \
    < "${OUTBOX_SETTINGS_SQL}"

  echo "[reset-and-install] Normalizing federationoutboxsettings.storefrontbaseurl to ${PUBLIC_URL}"
  docker compose -f "${COMPOSE_FILE}" exec -T "${POSTGRES_SERVICE}" psql -U "${DB_USER_VAL}" -d "${DB_NAME_VAL}" -v ON_ERROR_STOP=1 -c "
UPDATE \"Setting\"
SET \"Value\" = '${PUBLIC_URL}'
WHERE lower(\"Name\") = 'federationoutboxsettings.storefrontbaseurl';
" </dev/null

  echo "[reset-and-install] Restarting ${NOP_SERVICE} so Federation Outbox picks up seeded settings"
  docker compose -f "${COMPOSE_FILE}" restart "${NOP_SERVICE}" >/dev/null

  echo "[reset-and-install] Waiting for ${NOP_URL} after outbox settings restart"
  i=0
  HTTP_CODE=000
  while [ "$i" -lt "$WAIT_SECONDS" ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${NOP_URL}" || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
      echo "[reset-and-install] Storefront responded HTTP $HTTP_CODE after settings restart"
      break
    fi
    i=$((i + SLEEP))
    sleep $SLEEP
  done

  if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "302" ]; then
    echo "[reset-and-install] WARNING: storefront did not become ready after outbox settings restart (last code: ${HTTP_CODE})"
  fi
fi

echo "[reset-and-install] Done"
exit 0
