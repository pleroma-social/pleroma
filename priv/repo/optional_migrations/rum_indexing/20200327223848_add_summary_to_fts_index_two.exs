defmodule Pleroma.Repo.Migrations.AddSummaryToFtsIndexTwo do
  use Ecto.Migration

  def up do
    drop_if_exists(
      index(:objects, ["(to_tsvector('english', data->>'summary'))"],
        using: :gin,
        name: :objects_summary_fts
      )
    )

    alter table(:objects) do
      add(:fts_summary, :tsvector)
    end

    execute("""
    CREATE OR REPLACE FUNCTION objects_fts_update() RETURNS trigger AS $$
    begin
      new.fts_summary := to_tsvector('english', new.data->>'summary');
      new.fts_content := to_tsvector('english', new.data->>'content');
      return new;
    end
    $$ LANGUAGE plpgsql
    """)
  end

  def down do
    alter table(:objects) do
      remove(:fts_summary, :tsvector)
    end

    create_if_not_exists(
      index(:objects, ["(to_tsvector('english', data->>'summary'))"],
        using: :gin,
        name: :objects_summary_fts
      )
    )

    execute("""
    CREATE OR REPLACE FUNCTION objects_fts_update() RETURNS trigger AS $$
    begin
      new.fts_content := to_tsvector('english', new.data->>'content');
      return new;
    end
    $$ LANGUAGE plpgsql
    """)
  end
end
