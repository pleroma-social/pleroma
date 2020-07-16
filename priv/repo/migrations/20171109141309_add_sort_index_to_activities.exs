defmodule Pleroma.Repo.Migrations.AddSortIndexToActivities do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create(index(:activities, ["id desc nulls last"], concurrently: true))
  end
end
