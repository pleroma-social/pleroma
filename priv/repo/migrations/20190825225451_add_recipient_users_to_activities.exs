defmodule Pleroma.Repo.Migrations.AddRecipientUsersToActivities do
  use Ecto.Migration

  def change do
    alter table(:activities) do
      add :recipient_users, {:array, :string}
    end

    create_if_not_exists index(:activities, [:recipient_users], using: :gin)
  end
end
