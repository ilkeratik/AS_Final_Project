#!/usr/bin/env bash
# scripts/data/apply-northstar-seed.sh
# Apply Northstar Living Group product catalogues to running BU containers.
#
# BU-A  →  HomeStyle Living  (furniture, kitchen, bedding, lighting, garden, smart home, storage)
# BU-B  →  WorkForge Industrial (power tools, safety, lifting, welding, electrical, fasteners, workwear)
#
# Usage (both BUs):
#   ./scripts/data/apply-northstar-seed.sh
#
# Usage (single BU):
#   BU=a ./scripts/data/apply-northstar-seed.sh
#   BU=b ./scripts/data/apply-northstar-seed.sh
#
# Can also be called by reset-and-install.sh via SEED_PRODUCTS=northstar env var.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BU=${BU:-"both"}

apply_seed() {
  local bu_label="$1"     # bu-a or bu-b
  local container="$2"    # nopcommerce_bua_postgres or nopcommerce_bub_postgres
  local db_user="$3"      # nopcommerce_bua or nopcommerce_bub
  local sql_file="$4"     # absolute path to seed SQL

  echo "[northstar-seed] ────────────────────────────────────────────────────────"
  echo "[northstar-seed] Seeding ${bu_label} → container: ${container}"
  echo "[northstar-seed] SQL file: ${sql_file}"
  echo "[northstar-seed] ────────────────────────────────────────────────────────"

  if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
    echo "[northstar-seed] ERROR: container '${container}' is not running."
    echo "[northstar-seed] Start the stack first: ./platform.sh start --no-federation"
    return 1
  fi

  docker exec -i "${container}" \
    psql -U "${db_user}" -d nopcommerce -v ON_ERROR_STOP=1 \
    < "${sql_file}"

  echo "[northstar-seed] ✓ ${bu_label} seed applied."
}

case "$BU" in
  a|A|bu-a|BU-A)
    apply_seed "bu-a" "nopcommerce_bua_postgres" "nopcommerce_bua" \
      "${SCRIPT_DIR}/seed-bua-homestyle.sql"
    ;;
  b|B|bu-b|BU-B)
    apply_seed "bu-b" "nopcommerce_bub_postgres" "nopcommerce_bub" \
      "${SCRIPT_DIR}/seed-bub-workindustrial.sql"
    ;;
  both|*)
    apply_seed "bu-a" "nopcommerce_bua_postgres" "nopcommerce_bua" \
      "${SCRIPT_DIR}/seed-bua-homestyle.sql"
    echo ""
    apply_seed "bu-b" "nopcommerce_bub_postgres" "nopcommerce_bub" \
      "${SCRIPT_DIR}/seed-bub-workindustrial.sql"
    ;;
esac

echo ""
echo "[northstar-seed] ════════════════════════════════════════════════════════"
echo "[northstar-seed]  Northstar Living Group catalogues loaded"
echo "[northstar-seed]  BU-A HomeStyle Living  → http://localhost:5001"
echo "[northstar-seed]  BU-B WorkForge Industrial → http://localhost:5002"
echo "[northstar-seed] ════════════════════════════════════════════════════════"

