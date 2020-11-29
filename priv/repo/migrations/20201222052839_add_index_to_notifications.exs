defmodule Pleroma.Repo.Migrations.AddIndexToNotifications do
  use Ecto.Migration

  def change do
    create_if_not_exists(index(:notifications, [:seen, :notified_at, :type, :inserted_at]))
  end
end
