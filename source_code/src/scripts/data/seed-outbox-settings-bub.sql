-- Federation Outbox plugin settings for BU-B

DELETE FROM "Setting" WHERE "Name" ILIKE 'federationoutboxsettings.%';

INSERT INTO "Setting" ("Name", "Value", "StoreId")
VALUES
  ('federationoutboxsettings.storecode',           'bu-b',                    0),
  ('federationoutboxsettings.storename',           'WorkForge Industrial',    0),
  ('federationoutboxsettings.enabled',             'True',                    0),
  ('federationoutboxsettings.retainprocesseddays', '7',                       0),
  ('federationoutboxsettings.storefrontbaseurl',   'http://localhost:5002',   0);

SELECT 'BU-B outbox settings applied' AS status;


