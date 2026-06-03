#!/usr/bin/env bash
# scripts/bootstrap/reset-and-install-bu.sh
# Reset and install a fully isolated BU stack (BU-A or BU-B).
# Each BU has its own Postgres container, nopCommerce container, and data volume.
#
# Usage:
#   BUA_DB_PASS=... BUA_ADMIN_PASS=... BU=a ./scripts/bootstrap/reset-and-install-bu.sh          # install BU-A (fresh)
#   BUB_DB_PASS=... BUB_ADMIN_PASS=... BU=b ./scripts/bootstrap/reset-and-install-bu.sh          # install BU-B (fresh)
#   BU=a REMOVE_VOLUMES=false ./scripts/bootstrap/reset-and-install-bu.sh  # reinstall without wiping data
#
# Run both simultaneously (parallel install):
#   BUA_DB_PASS=... BUA_ADMIN_PASS=... BU=a ./scripts/bootstrap/reset-and-install-bu.sh &
#   BUB_DB_PASS=... BUB_ADMIN_PASS=... BU=b ./scripts/bootstrap/reset-and-install-bu.sh &
#   wait
set -eu

PROJECT_ROOT=${PROJECT_ROOT:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"}
BU=${BU:-"a"}

case "$BU" in
  a|A|bu-a|BU-A)
    BU_LABEL="bu-a"
    COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.bua.yml"
    POSTGRES_SERVICE="postgres-bua"
    NOP_SERVICE="nopcommerce-bua"
    NOP_WEB_CONTAINER="nopcommerce_bua_web"
    INSTALL_SERVICE="nopcommerce-auto-install"
    INSTALL_CONTAINER_FILTER="nopcommerce_bua_install"
    NOP_URL="http://localhost:5001"
    DB_SERVER="postgres-bua"
    DB_NAME="nopcommerce"
    DB_USER="nopcommerce_bua"
    DB_PASS=${DB_PASS:-${BUA_DB_PASS:-""}}
    APPDATA_HOST_DIR="${PROJECT_ROOT}/_appdata-bua"
    ;;
  b|B|bu-b|BU-B)
    BU_LABEL="bu-b"
    COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.bub.yml"
    POSTGRES_SERVICE="postgres-bub"
    NOP_SERVICE="nopcommerce-bub"
    NOP_WEB_CONTAINER="nopcommerce_bub_web"
    INSTALL_SERVICE="nopcommerce-auto-install"
    INSTALL_CONTAINER_FILTER="nopcommerce_bub_install"
    NOP_URL="http://localhost:5002"
    DB_SERVER="postgres-bub"
    DB_NAME="nopcommerce"
    DB_USER="nopcommerce_bub"
    DB_PASS=${DB_PASS:-${BUB_DB_PASS:-""}}
    APPDATA_HOST_DIR="${PROJECT_ROOT}/_appdata-bub"
    ;;
  *)
    echo "[reset-bu] ERROR: BU must be 'a' or 'b' (got '${BU}')"
    exit 1
    ;;
esac

if [ -z "${DB_PASS}" ]; then
  echo "[reset-bu] ERROR: DB_PASS is required (set DB_PASS or BUA_DB_PASS/BUB_DB_PASS)."
  exit 1
fi

echo "[reset-bu] ================================================="
echo "[reset-bu] Target BU : ${BU_LABEL}"
echo "[reset-bu] Compose   : ${COMPOSE_FILE}"
echo "[reset-bu] Web URL   : ${NOP_URL}"
echo "[reset-bu] DB        : postgres://${DB_USER}@${DB_SERVER}/${DB_NAME}"
echo "[reset-bu] Appdata   : ${APPDATA_HOST_DIR}"
echo "[reset-bu] ================================================="

# Ensure the per-BU appdata directory exists before passing it to the installer
mkdir -p "${APPDATA_HOST_DIR}"

# Delegate to the generic installer with all BU-specific overrides
COMPOSE_FILE="${COMPOSE_FILE}" \
POSTGRES_SERVICE="${POSTGRES_SERVICE}" \
NOP_SERVICE="${NOP_SERVICE}" \
NOP_WEB_CONTAINER="${NOP_WEB_CONTAINER}" \
INSTALL_SERVICE="${INSTALL_SERVICE}" \
INSTALL_CONTAINER_FILTER="${INSTALL_CONTAINER_FILTER}" \
NOP_URL="${NOP_URL}" \
DB_SERVER="${DB_SERVER}" \
DB_NAME="${DB_NAME}" \
DB_USER="${DB_USER}" \
DB_PASS="${DB_PASS}" \
APPDATA_HOST_DIR="${APPDATA_HOST_DIR}" \
REMOVE_VOLUMES="${REMOVE_VOLUMES:-true}" \
CLEAN_IMAGES="${CLEAN_IMAGES:-true}" \
SPLIT_AFTER_INSTALL="${SPLIT_AFTER_INSTALL:-true}" \
SPLIT_ROLE="${BU_LABEL}" \
  "${PROJECT_ROOT}/scripts/bootstrap/reset-and-install.sh"

