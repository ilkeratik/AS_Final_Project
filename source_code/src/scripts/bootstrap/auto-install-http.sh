#!/bin/sh
# scripts/bootstrap/auto-install-http.sh
# POSIX sh - idempotent installer poster for nopCommerce HTTP install flow
# Usage: set env vars as needed then run (example below)
set -eu

NOP_URL=${NOP_URL:-"http://localhost:5001"}        # the running nopCommerce base URL
DB_SERVER=${DB_SERVER:-"postgres"}
DB_NAME=${DB_NAME:-"nopcommerce"}
DB_USER=${DB_USER:-"nopcommerce"}
DB_PASS=${DB_PASS:-"nopcommerce123"}
ADMIN_EMAIL=${ADMIN_EMAIL:-"admin@example.com"}
ADMIN_PASS=${ADMIN_PASS:-"admin@123"}
INSTALL_SAMPLE_DATA=${INSTALL_SAMPLE_DATA:-"false"} # true|false
DATA_PROVIDER=${DATA_PROVIDER:-"PostgreSQL"}       # PostgreSQL or SqlServer or MySql

# timeouts
WAIT_SECONDS=${WAIT_SECONDS:-60}
SLEEP=1
POST_RETRIES=${POST_RETRIES:-3}
POST_RETRY_SLEEP=${POST_RETRY_SLEEP:-2}

echo "[auto-install] Using NOP_URL=${NOP_URL}"
echo "[auto-install] Waiting up to ${WAIT_SECONDS}s for ${NOP_URL}/install ..."

i=0
HTTP_CODE=000
while [ "$i" -lt "$WAIT_SECONDS" ]; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${NOP_URL}/install" || echo "000")
  if [ "$HTTP_CODE" != "000" ]; then
    echo "[auto-install] /install responded HTTP $HTTP_CODE"
    break
  fi
  i=$((i + SLEEP))
  sleep $SLEEP
done

if [ "$HTTP_CODE" = "000" ]; then
  echo "[auto-install] ERROR: /install did not respond after ${WAIT_SECONDS}s"
  exit 1
fi

# fetch install page body + cookies (follow redirects)
echo "[auto-install] Fetching install page (following redirects)..."
INSTALL_PAGE=$(mktemp)
COOKIE_JAR=$(mktemp)
trap 'rm -f "$INSTALL_PAGE" "$COOKIE_JAR"' EXIT

# Get the page with redirects followed and capture final URL
FINAL_URL=$(curl -sL -c "$COOKIE_JAR" -w "%{url_effective}" -o "$INSTALL_PAGE" "${NOP_URL}/install" || echo "")
PAGE_BYTES=$(wc -c <"$INSTALL_PAGE" || echo 0)
echo "[auto-install] Got ${PAGE_BYTES} bytes, final URL: ${FINAL_URL}"

# Check if we're in a redirect loop (still at /install after following redirects)
case "$FINAL_URL" in
  *"/install"*)
    echo "[auto-install] Still at /install page after redirects, checking content..."
    ;;
  *)
    # Redirected away from /install - check if it's the homepage
    if [ "$PAGE_BYTES" -gt 1000 ]; then
      echo "[auto-install] Redirected away from /install to ${FINAL_URL} - likely already installed."
      # Verify by checking if page contains typical nopCommerce elements
      if grep -qiE "nopCommerce|<title>|home" "$INSTALL_PAGE"; then
        echo "[auto-install] nopCommerce already installed (redirected to storefront)."
        exit 0
      fi
    fi
    ;;
esac

# if page contains "already installed" or "Installation completed", exit
if grep -qiE "already installed|installation completed|installation is completed" "$INSTALL_PAGE"; then
  echo "[auto-install] nopCommerce already installed (install page indicates installed)."
  exit 0
fi

# Check if we have an actual install form (form fields present)
if ! grep -qE "AdminEmail|AdminPassword|InstallSampleData" "$INSTALL_PAGE"; then
  echo "[auto-install] WARNING: Install page loaded but doesn't contain expected form fields."
  echo "[auto-install] This might indicate the site is configured but database needs initialization."
fi

# extract antiforgery token (if present)
CSRF=$(sed -n 's/.*name="__RequestVerificationToken"[^>]*value="\([^"]*\)".*/\1/p' "$INSTALL_PAGE" | head -1 || true)
if [ -n "$CSRF" ]; then
  echo "[auto-install] Found antiforgery token"
else
  echo "[auto-install] No antiforgery token found; will try POST without token"
fi

echo "[auto-install] Submitting install form..."
attempt=1
while [ "$attempt" -le "$POST_RETRIES" ]; do
  RESPONSE=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X POST "${NOP_URL}/install" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "__RequestVerificationToken=${CSRF}" \
    --data-urlencode "AdminEmail=${ADMIN_EMAIL}" \
    --data-urlencode "AdminPassword=${ADMIN_PASS}" \
    --data-urlencode "ConfirmPassword=${ADMIN_PASS}" \
    --data-urlencode "InstallSampleData=${INSTALL_SAMPLE_DATA}" \
    --data-urlencode "SubscribeNewsletters=true" \
    --data-urlencode "DataProvider=${DATA_PROVIDER}" \
    --data-urlencode "CreateDatabaseIfNotExists=false" \
    --data-urlencode "ConnectionStringRaw=false" \
    --data-urlencode "ServerName=${DB_SERVER}" \
    --data-urlencode "DatabaseName=${DB_NAME}" \
    --data-urlencode "IntegratedSecurity=false" \
    --data-urlencode "Username=${DB_USER}" \
    --data-urlencode "Password=${DB_PASS}" \
    --data-urlencode "UseCustomCollation=false" \
    -w "\nHTTP_CODE:%{http_code}" )

  HTTP_CODE=$(echo "$RESPONSE" | awk -F'HTTP_CODE:' '{print $2}' | tr -d '\r\n' || echo "")
  BODY=$(echo "$RESPONSE" | sed 's/HTTP_CODE:.*$//')

  echo "[auto-install] Response HTTP code: ${HTTP_CODE}"
  echo "[auto-install] Response size: $(printf "%s" "$BODY" | wc -c) bytes"

  if [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ] || [ "$HTTP_CODE" = "307" ] || [ "$HTTP_CODE" = "308" ]; then
    echo "[auto-install] Install POST redirected (likely success)."
    exit 0
  fi

  # nopCommerce returns HTTP 200 with a "restart application" throbber page on success.
  # This marker is only present on the post-install page, never on the install form,
  # so detecting it lets us stop immediately instead of re-running a non-idempotent install.
  if printf "%s" "$BODY" | grep -qi "restartapplication"; then
    echo "[auto-install] Installation completed (restart page returned)."
    exit 0
  fi

  # Surface a real setup error and stop retrying - retrying would only duplicate seed data.
  if printf "%s" "$BODY" | grep -qi "Setup failed"; then
    echo "[auto-install] ERROR: installation reported a setup failure:"
    printf "%s" "$BODY" | grep -oiE "Setup failed[^<]*" | head -1
    exit 3
  fi

  if printf "%s" "$BODY" | grep -qiE "already installed|installation completed|Installation successful|Installation is completed|Admin area"; then
    echo "[auto-install] Installation appears successful or already done."
    exit 0
  fi

  if [ "$attempt" -lt "$POST_RETRIES" ]; then
    echo "[auto-install] Install attempt ${attempt} did not succeed, retrying in ${POST_RETRY_SLEEP}s..."
    sleep "$POST_RETRY_SLEEP"
  fi

  attempt=$((attempt + 1))
done

# Post-check: try simple health endpoint or homepage (no crash)
echo "[auto-install] Verifying home page..."
HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${NOP_URL}/" || echo "000")
echo "[auto-install] Home page HTTP code: ${HEALTH_CODE}"
if [ "$HEALTH_CODE" = "200" ] || [ "$HEALTH_CODE" = "302" ]; then
  echo "[auto-install] Done — site responded."
  exit 0
fi

echo "[auto-install] Warning: install posted but site not healthy. Check logs."
exit 2

# Example usage:
# NOP_URL=http://localhost:5001 DB_SERVER=postgres DB_NAME=nopcommerce DB_USER=nopcommerce DB_PASS=nopcommerce123 \
#   ADMIN_EMAIL=admin@example.com ADMIN_PASS=admin@123 ./scripts/bootstrap/auto-install-http.sh

