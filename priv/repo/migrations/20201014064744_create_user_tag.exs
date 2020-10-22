defmodule Pleroma.Repo.Migrations.CreateUserTag do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:users_tags, primary_key: false) do
      add(:tag_id, references(:tags, on_delete: :delete_all))
      add(:user_id, references(:users, type: :uuid, on_delete: :delete_all))
    end

    create_if_not_exists(index(:users_tags, [:tag_id]))
    create_if_not_exists(index(:users_tags, [:user_id]))
    create_if_not_exists(unique_index(:users_tags, [:user_id, :tag_id]))
  end
end
