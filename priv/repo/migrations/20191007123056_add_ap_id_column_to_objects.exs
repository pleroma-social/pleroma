defmodule Pleroma.Repo.Migrations.AddApIdColumnToObjects do
  use Ecto.Migration

  def change do
    alter table(:objects) do
      add :ap_id, :string
    end

    create unique_index(:objects, [:ap_id], concurrently: true)
  end
end
