defmodule Pleroma.Repo.Migrations.AddLastKnownIpToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:last_known_ip, :inet)
    end

    create(index(:users, [:last_known_ip]))
  end
end
