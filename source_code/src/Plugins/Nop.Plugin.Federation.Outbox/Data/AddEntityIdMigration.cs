using FluentMigrator;
using Nop.Data.Migrations;

namespace Nop.Plugin.Federation.Outbox.Data;

/// <summary>
/// Adds the EntityId column so the startup seed task can query "has product X ever been
/// enqueued?" without parsing MessageId strings or JSON payloads.
/// </summary>
[NopMigration("2026-06-02 10:00:00", "Federation.Outbox 1.2.0 — add EntityId for idempotent startup seeding", MigrationProcessType.Update)]
public class AddEntityIdMigration : AutoReversingMigration
{
    private const string TableName = "OutboxMessage";

    public override void Up()
    {
        if (!Schema.Table(TableName).Column("EntityId").Exists())
        {
            Alter.Table(TableName)
                .AddColumn("EntityId").AsInt32().Nullable();
        }
    }
}

