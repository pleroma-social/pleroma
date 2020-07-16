defmodule Pleroma.Repo.Migrations.CreateActivitiesInReplyToIndex do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create(
      index(:activities, ["(data->'object'->>'inReplyTo')"],
        concurrently: true,
        name: :activities_in_reply_to
      )
    )
  end
end
