defmodule Pleroma.Repo.Migrations.ImportLegacyTagsToUsersTags do
  use Ecto.Migration

  def up do
    Ecto.Adapters.SQL.query(
      Pleroma.Repo,
      import_user_tags(),
      [],
      timeout: :infinity
    )

    alter table(:users) do
      remove_if_exists(:tags, {:array, :string})
    end

    drop_if_exists(index(:users, [:tags]))
  end

  def down do
    alter table(:users) do
      add_if_not_exists(:tags, {:array, :string}, default: [], null: false)
    end

    create_if_not_exists(index(:users, [:tags], using: :gin))

    flush()

    Ecto.Adapters.SQL.query(
      Pleroma.Repo,
      restore_tags_column(),
      [],
      timeout: :infinity
    )
  end

  defp import_user_tags do
    """
    INSERT INTO users_tags(user_id, tag_id)
    SELECT user_tags.user_id, tags.id
     FROM (
     SELECT  DISTINCT TRIM(unnest(tags)) as "tag", id as "user_id"
       FROM users ) as "user_tags"
     INNER JOIN tags as tags on tags.name = user_tags."tag"
     ON CONFLICT DO NOTHING
    """
  end

  defp restore_tags_column do
    """
    UPDATE
      users
    SET
      tags = tags_query.tags_array,
      updated_at = now()
    FROM (
      SELECT user_id, array_agg(tags.name) as tags_array
      FROM users_tags
        INNER JOIN users ON users.id = user_id
        INNER JOIN tags ON tags.id = tag_id
      GROUP BY user_id
    ) as tags_query
    WHERE tags_query.user_id = users.id
    """
  end
end
