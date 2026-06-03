#!/usr/bin/env bash
# Resume (unpause) BU-A Postgres container
CONTAINER_NAME=${1:-nopcommerce_bua_postgres}

echo "Unpausing container $CONTAINER_NAME"
docker unpause "$CONTAINER_NAME"
echo "Unpaused. The BU-A Outbox hosted service will seed any missing events automatically on next app start."
echo "To trigger immediately: docker compose -f docker-compose.bua.yml restart nopcommerce-bua"

