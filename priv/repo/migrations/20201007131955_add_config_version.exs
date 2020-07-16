defmodule Pleroma.Repo.Migrations.AddConfigVersion do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:config_versions) do
      add(:backup, :binary)
      add(:current, :boolean)

      timestamps()
    end

    create_if_not_exists(unique_index(:config_versions, [:current], where: "current = true"))
  end
end
