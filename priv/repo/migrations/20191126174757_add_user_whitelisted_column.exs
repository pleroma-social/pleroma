defmodule Pleroma.Repo.Migrations.AddUserWhitelistedColumn do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add_if_not_exists(:whitelist, {:array, :text}, default: [])
    end
  end
end
