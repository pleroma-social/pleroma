defmodule Pleroma.Repo.Migrations.AddBlockCacheToActivities do
  use Ecto.Migration

  def up do
    alter table(:activities) do
      add(:block_cache, {:array, :string})
    end

    create_if_not_exists(index(:activities, [:block_cache], using: :gin))

    statement = """
    create function activities_block_cache_update() returns trigger as $$
    DECLARE to_ary varchar[];
    begin
      if new.data->>'type' = 'Announce' then
        SELECT array_cat(array_agg(ary)::varchar[], array_agg(split_part(ary, '/', 3))::varchar[])
        INTO to_ary
        FROM jsonb_array_elements_text(new.data->'to') AS ary;
        
        new.block_cache := array_cat(ARRAY[new.actor, split_part(new.actor, '/', 3)], to_ary);
      else
        new.block_cache := array_cat(ARRAY[new.actor, split_part(new.actor, '/', 3)], new.recipients);
      end if;
      return new;
    end
    $$ language plpgsql
    """

    execute(statement)

    execute(
      "create trigger activities_block_cache_update before insert or update on activities for each row execute procedure activities_block_cache_update()"
    )
  end

  def down do
    execute("drop trigger if exists activities_block_cache_update on activities")
    execute("drop function if exists activities_block_cache_update()")

    drop_if_exists(index(:activities, [:block_cache], using: :gin))

    alter table(:activities) do
      remove(:block_cache, {:array, :string})
    end
  end
end
