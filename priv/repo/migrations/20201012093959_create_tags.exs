defmodule Pleroma.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def up do
    create_if_not_exists table(:tags) do
      add(:name, :string, null: false)
      timestamps()
    end

    create_if_not_exists(unique_index(:tags, :name))
    flush()

    Ecto.Adapters.SQL.query(
      Pleroma.Repo,
      collect_user_tags_query(),
      [],
      timeout: :infinity
    )
  end

  def down do
    drop_if_exists(table(:tags))
    drop_if_exists(unique_index(:tags, :name))
  end

  defp collect_user_tags_query do
    """
    INSERT INTO tags(name, inserted_at, updated_at)
    SELECT DISTINCT TRIM(unnest(tags)), now(), now() from users
    ON CONFLICT DO NOTHING
    """
  end
end
