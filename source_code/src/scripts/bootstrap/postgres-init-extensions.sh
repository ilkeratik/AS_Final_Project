#!/bin/sh
set -eu

TARGET_DB=${POSTGRES_DB:-${PGDATABASE:-"nopcommerce"}}
TARGET_USER=${POSTGRES_USER:-${PGUSER:-"postgres"}}

echo "Installing citext extension in database '${TARGET_DB}' as user '${TARGET_USER}'..."
psql -v ON_ERROR_STOP=1 --username "${TARGET_USER}" --dbname "${TARGET_DB}" -c "CREATE EXTENSION IF NOT EXISTS citext;"
echo "citext extension installed"

