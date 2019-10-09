defmodule Pleroma.Repo.Migrations.AddApIdColumnToObjects do
  use Ecto.Migration

  def change do
    alter table(:objects) do
      add :ap_id, :string
    end
  end
end
