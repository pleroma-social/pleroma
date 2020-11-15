defmodule Pleroma.Repo.Migrations.ChangeObjectIndexOnCreateActivities do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    drop_if_exists(
      index(:activities, ["(coalesce(data->'object'->>'id', data->>'object'))"],
        name: :activities_create_objects_index
      )
    )

    create(
      index(:activities, ["(coalesce(data->'object'->>'id', data->>'object'))"],
        name: :activities_create_objects_index,
        concurrently: true,
        where: "data->>'type' = 'Create'"
      )
    )
  end
end
