defmodule Pleroma.Repo.Migrations.AddTagsFieldToActivities do
  use Ecto.Migration

  def up do
    alter table(:activities) do
      add(:tags, {:array, :string})
    end

    execute("CREATE FUNCTION activities_tags_update() RETURNS trigger AS $$
    begin
      IF new.data->>'type' = 'Create' THEN
        select array_agg(tags->>0) into new.tags from (select jsonb_array_elements(data->'tag') tags from objects where jsonb_typeof(data->'tag') = 'array' and objects.data->>'id' = new.data->>'object') as tags where jsonb_typeof(tags) = 'string';
      END IF;
      return new;
    end
    $$ LANGUAGE plpgsql")

    execute(
      "create trigger update_activity_tags before insert or update on activities for each row execute procedure activities_tags_update()"
    )

    create_if_not_exists(index(:activities, [:tags], using: :gin))
  end

  def down do
    drop("trigger if exists update_activity_tags")
    drop("function if exists activities_tags_update")

    alter table(:activities) do
      remove(:tags, {:array, :string})
    end

    drop_if_exists(index(:activities, [:tags], using: :gin))
  end
end
