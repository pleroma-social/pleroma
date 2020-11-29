defmodule Pleroma.Repo.Migrations.AddNotifiedAtToNotifications do
  use Ecto.Migration

  def up do
    alter table(:notifications) do
      add_if_not_exists(:notified_at, :naive_datetime)
    end
  end

  def down do
    alter table(:notifications) do
      remove_if_exists(:notified_at, :naive_datetime)
    end
  end
end
