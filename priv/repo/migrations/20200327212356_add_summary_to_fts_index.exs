defmodule Pleroma.Repo.Migrations.AddSummaryToFtsIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists(
      index(:objects, ["(to_tsvector('english', data->>'summary'))"],
        using: :gin,
        name: :objects_summary_fts
      )
    )
  end
end
