-- Federation Outbox plugin settings for BU-A
-- Setting names follow nopCommerce convention: lowercased type.property

DELETE FROM "Setting" WHERE "Name" ILIKE 'federationoutboxsettings.%';

INSERT INTO "Setting" ("Name", "Value", "StoreId")
VALUES
  ('federationoutboxsettings.storecode',           'bu-a',                    0),
  ('federationoutboxsettings.storename',           'HomeStyle Living',        0),
  ('federationoutboxsettings.enabled',             'True',                    0),
  ('federationoutboxsettings.retainprocesseddays', '7',                       0),
  ('federationoutboxsettings.storefrontbaseurl',   'http://localhost:5001',   0);

SELECT 'BU-A outbox settings applied' AS status;


