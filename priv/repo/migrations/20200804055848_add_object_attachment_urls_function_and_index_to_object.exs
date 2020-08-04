defmodule Pleroma.Repo.Migrations.AddObjectAttachmentUrlsFunctionAndIndexToObject do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    """
    CREATE OR REPLACE FUNCTION object_attachment_urls(j jsonb)
    RETURNS text[] AS $$
    BEGIN
    RETURN ARRAY(
        SELECT elem->> 'href'
        FROM jsonb_array_elements(j #> '{url}') elem
        WHERE jsonb_typeof(j::jsonb #> '{url}') = 'array'
    );
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    """
    |> execute()

    create(
      index(:objects, ["object_attachment_urls(data)"],
        name: :object_attachment_urls_index,
        concurrently: true
      )
    )
  end

  def down do
    drop_if_exists(
      index(:objects, ["object_attachment_urls(data)"], name: :object_attachment_urls_index)
    )

    execute("drop function if exists object_attachment_urls(j jsonb)")
  end
end
