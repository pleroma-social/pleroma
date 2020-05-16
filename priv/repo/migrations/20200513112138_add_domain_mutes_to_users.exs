defmodule Pleroma.Repo.Migrations.AddDomainMutesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add_if_not_exists(:domain_mutes, {:array, :text}, default: [])
    end
  end
end
