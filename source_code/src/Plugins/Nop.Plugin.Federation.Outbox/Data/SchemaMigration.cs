using FluentMigrator;
using Nop.Data.Extensions;
using Nop.Data.Migrations;
using Nop.Plugin.Federation.Outbox.Domain;

namespace Nop.Plugin.Federation.Outbox.Data;

[NopMigration("2026-05-31 10:00:00", "Federation.Outbox 1.0.0 — initial schema", MigrationProcessType.Installation)]
public class SchemaMigration : AutoReversingMigration
{
    public override void Up()
    {
        Create.TableFor<OutboxMessage>();
    }
}

