using FluentMigrator;
using Nop.Data.Migrations;

namespace Nop.Plugin.Federation.Outbox.Data;

/// <summary>
/// Adds the CorrelationId column for distributed tracing (§6.3 — Observability).
/// Propagated as X-Correlation-Id Kafka header by the KafkaRelay.
/// </summary>
[NopMigration("2026-05-31 11:00:00", "Federation.Outbox 1.1.0 — add CorrelationId for distributed tracing", MigrationProcessType.Update)]
public class AddCorrelationIdMigration : AutoReversingMigration
{
    private const string TableName = "OutboxMessage";

    public override void Up()
    {
        if (!Schema.Table(TableName).Column("CorrelationId").Exists())
        {
            Alter.Table(TableName)
                .AddColumn("CorrelationId").AsString(36).Nullable();
        }
    }
}

