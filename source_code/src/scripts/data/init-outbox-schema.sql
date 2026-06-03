-- Create OutboxMessage table (Federation.Outbox plugin schema)
CREATE TABLE IF NOT EXISTS "OutboxMessage" (
    "Id"             SERIAL PRIMARY KEY,
    "MessageId"      VARCHAR(200)  NOT NULL,
    "StoreCode"      VARCHAR(50)   NOT NULL,
    "StoreName"      VARCHAR(200)  NOT NULL,
    "EventType"      VARCHAR(50)   NOT NULL,
    "Topic"          VARCHAR(200)  NOT NULL,
    "Payload"        TEXT          NOT NULL,
    "CreatedOnUtc"   TIMESTAMP     NOT NULL,
    "ProcessedOnUtc" TIMESTAMP     NULL,
    "LastError"      VARCHAR(2000) NULL,
    "Attempts"       INT           NOT NULL DEFAULT 0,
    "CorrelationId"  VARCHAR(36)   NULL
);

CREATE INDEX IF NOT EXISTS "IX_OutboxMessage_MessageId"
    ON "OutboxMessage" ("MessageId");

CREATE INDEX IF NOT EXISTS "IX_OutboxMessage_ProcessedOnUtc"
    ON "OutboxMessage" ("ProcessedOnUtc");

-- Record both migrations so nopCommerce won't re-run them on next startup
INSERT INTO "MigrationVersionInfo" ("Version", "AppliedOn", "Description")
VALUES
  (20260531100000, NOW(), 'Federation.Outbox 1.0.0 — initial schema'),
  (20260531110000, NOW(), 'Federation.Outbox 1.1.0 — add CorrelationId for distributed tracing')
ON CONFLICT ("Version") DO NOTHING;

SELECT 'OutboxMessage table ready' AS status;

