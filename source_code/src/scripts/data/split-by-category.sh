#!/usr/bin/env bash
# scripts/data/split-by-category.sh
# Assign each BU its own product catalogue by category.
#   BU-A: Home & Living           (categories 1,2,4,5,6,7,8,13)
#   BU-B: Industrial & Trade      (categories 3,9,10,11,12,14,15,16)
#
# Runs SQL via docker compose exec — no local psql install required.
#
# Required env vars (set by bootstrap/reset-and-install.sh or caller):
#   SPLIT_ROLE        - bu-a | bu-b           (default: bu-a)
#   COMPOSE_FILE      - path to compose file  (default: <repo>/docker-compose.bua.yml)
#   POSTGRES_SERVICE  - compose service name  (default: postgres-bua)
#   DB_USER           - postgres user         (default: nopcommerce_bua)
#   DB_NAME           - database name         (default: nopcommerce)
#
# Stand-alone usage:
#   SPLIT_ROLE=bu-a ./scripts/data/split-by-category.sh
#   SPLIT_ROLE=bu-b COMPOSE_FILE=docker-compose.bub.yml \
#     POSTGRES_SERVICE=postgres-bub DB_USER=nopcommerce_bub \
#     ./scripts/data/split-by-category.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../.."

SPLIT_ROLE=${SPLIT_ROLE:-"bu-a"}
COMPOSE_FILE=${COMPOSE_FILE:-"${PROJECT_ROOT}/docker-compose.bua.yml"}
POSTGRES_SERVICE=${POSTGRES_SERVICE:-"postgres-bua"}
DB_USER=${DB_USER:-"nopcommerce_bua"}
DB_NAME=${DB_NAME:-"nopcommerce"}

psql_exec() {
  docker compose -f "${COMPOSE_FILE}" exec -T "${POSTGRES_SERVICE}" \
    psql -U "${DB_USER}" -d "${DB_NAME}" "$@"
}

echo "[split-by-category] ROLE=${SPLIT_ROLE}, DB=${DB_NAME}, service=${POSTGRES_SERVICE}"

case "$SPLIT_ROLE" in
  bu-a)
    CATEGORY_IDS="1,2,4,5,6,7,8,13"
    STORE_NAME="HomeStyle Living"
    STORE_COMPANY="HomeStyle Living Ltd."
    STORE_URL="http://localhost:5001/"
    echo "[split-by-category] BU-A catalogue: Home & Living"
    ;;
  bu-b)
    CATEGORY_IDS="3,9,10,11,12,14,15,16"
    STORE_NAME="WorkForge Industrial"
    STORE_COMPANY="WorkForge Industrial Ltd."
    STORE_URL="http://localhost:5002/"
    echo "[split-by-category] BU-B catalogue: Industrial & Trade"
    ;;
  *)
    echo "[split-by-category] ERROR: SPLIT_ROLE must be 'bu-a' or 'bu-b' (got '${SPLIT_ROLE}')"
    exit 1
    ;;
esac

echo "[split-by-category] Pre-split state:"
psql_exec -c "SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE \"Published\") AS published FROM \"Product\";"

echo "[split-by-category] Applying split..."
psql_exec <<SQL
-- Hide products not belonging to this BU's categories
UPDATE "Product"
SET "Published" = false
WHERE "Id" NOT IN (
  SELECT DISTINCT pcm."ProductId"
  FROM "Product_Category_Mapping" pcm
  WHERE pcm."CategoryId" IN (${CATEGORY_IDS})
)
AND "Published" = true;

-- Hide categories not belonging to this BU
UPDATE "Category"
SET "Published" = false, "ShowOnHomepage" = false
WHERE "Id" NOT IN (${CATEGORY_IDS});

-- Brand the primary store (ID=1) and normalise its URL
UPDATE "Store"
SET "Name" = '${STORE_NAME}',
    "CompanyName" = '${STORE_COMPANY}',
    "Url" = '${STORE_URL}'
WHERE "Id" = 1;

-- Normalise ALL store URLs (sample data may create stores 2, 3 with wrong/empty URLs)
UPDATE "Store"
SET "Url" = '${STORE_URL}'
WHERE "Url" IS DISTINCT FROM '${STORE_URL}';

-- Remove extra sample-data stores so only the primary BU store exists
DELETE FROM "Store" WHERE "Id" != 1;

-- Fix any residual internal Docker hostname URLs in settings (e.g. swiper slides)
UPDATE "Setting"
SET "Value" = replace(replace("Value",
      'http://nopcommerce-bua/', '${STORE_URL}'),
      'http://nopcommerce-bub/', '${STORE_URL}')
WHERE "Value" LIKE '%nopcommerce-bu%';
SQL

echo "[split-by-category] Post-split state:"
psql_exec -c "SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE \"Published\") AS published, COUNT(*) FILTER (WHERE NOT \"Published\") AS hidden FROM \"Product\";"

echo "[split-by-category] Visible products by category:"
psql_exec -c "
SELECT c.\"Name\" AS category, COUNT(DISTINCT p.\"Id\") AS products
FROM \"Category\" c
JOIN \"Product_Category_Mapping\" pcm ON c.\"Id\" = pcm.\"CategoryId\"
JOIN \"Product\" p ON pcm.\"ProductId\" = p.\"Id\" AND p.\"Published\" = true
WHERE c.\"Id\" IN (${CATEGORY_IDS})
GROUP BY c.\"Name\"
ORDER BY c.\"Name\";"

echo "[split-by-category] Done — store branded as '${STORE_NAME}'"
