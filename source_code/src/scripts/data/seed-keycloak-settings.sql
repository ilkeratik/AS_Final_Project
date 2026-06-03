-- seed-keycloak-settings.sql
-- Seeds KeycloakAuthenticationSettings and activates the plugin for the store.
-- Usage:
--   BU-A:  docker exec nopcommerce_bua_postgres psql -U nopcommerce_bua -d nopcommerce -v CLIENT_ID=bu-a-client -v CLIENT_SECRET=bu-a-secret -f /tmp/seed-keycloak-settings.sql
--   BU-B:  docker exec nopcommerce_bub_postgres psql -U nopcommerce_bub -d nopcommerce -v CLIENT_ID=bu-b-client -v CLIENT_SECRET=bu-b-secret -f /tmp/seed-keycloak-settings.sql
--
-- Variables (pass with -v):
--   CLIENT_ID      Keycloak client ID for this BU (e.g. bu-a-client)
--   CLIENT_SECRET  Keycloak client secret

-- Activate the Keycloak external auth plugin
INSERT INTO "Setting" ("Name", "Value", "StoreId")
VALUES ('externalauthenticationsettings.activeauthenticationmethodsystemnames', 'ExternalAuth.Keycloak', 0)
ON CONFLICT ("Name", "StoreId") DO UPDATE SET "Value" = 'ExternalAuth.Keycloak';

-- Plugin settings (Authority is public-facing localhost; MetadataAddress is internal Docker URL)
INSERT INTO "Setting" ("Name", "Value", "StoreId") VALUES
  ('keycloakauthenticationsettings.authority',       'http://localhost:8080/realms/nop-federation', 0),
  ('keycloakauthenticationsettings.metadataaddress', 'http://keycloak:8080/realms/nop-federation/.well-known/openid-configuration', 0),
  ('keycloakauthenticationsettings.validissuer',     'http://localhost:8080/realms/nop-federation', 0),
  ('keycloakauthenticationsettings.clientid',        :'CLIENT_ID', 0),
  ('keycloakauthenticationsettings.clientsecret',    :'CLIENT_SECRET', 0)
ON CONFLICT ("Name", "StoreId") DO UPDATE SET "Value" = EXCLUDED."Value";

