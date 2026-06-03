using FluentMigrator.Builders.Create.Table;
using Nop.Data.Mapping.Builders;
using Nop.Plugin.Federation.Outbox.Domain;

namespace Nop.Plugin.Federation.Outbox.Data;

public class OutboxMessageBuilder : NopEntityBuilder<OutboxMessage>
{
    public override void MapEntity(CreateTableExpressionBuilder table)
    {
        table
            .WithColumn(nameof(OutboxMessage.MessageId)).AsString(200).NotNullable().Unique()
            .WithColumn(nameof(OutboxMessage.StoreCode)).AsString(50).NotNullable()
            .WithColumn(nameof(OutboxMessage.StoreName)).AsString(200).NotNullable()
            .WithColumn(nameof(OutboxMessage.EventType)).AsString(50).NotNullable()
            .WithColumn(nameof(OutboxMessage.Topic)).AsString(200).NotNullable()
            .WithColumn(nameof(OutboxMessage.Payload)).AsString(int.MaxValue).NotNullable()
            .WithColumn(nameof(OutboxMessage.CreatedOnUtc)).AsDateTime().NotNullable()
            .WithColumn(nameof(OutboxMessage.ProcessedOnUtc)).AsDateTime().Nullable().Indexed()
            .WithColumn(nameof(OutboxMessage.LastError)).AsString(2000).Nullable()
            .WithColumn(nameof(OutboxMessage.Attempts)).AsInt32().NotNullable().WithDefaultValue(0)
            .WithColumn(nameof(OutboxMessage.EntityId)).AsInt32().Nullable();
    }
}

