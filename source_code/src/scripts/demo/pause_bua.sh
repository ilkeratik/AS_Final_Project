#!/usr/bin/env bash
# Pause BU-A Postgres container
CONTAINER_NAME=${1:-nopcommerce_bua_postgres}

echo "Pausing container $CONTAINER_NAME"
docker pause "$CONTAINER_NAME"
echo "Paused. To resume: ./scripts/demo/resume_bua.sh $CONTAINER_NAME"

