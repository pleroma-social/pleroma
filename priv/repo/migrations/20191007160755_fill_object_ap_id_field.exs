defmodule Pleroma.Repo.Migrations.FillObjectApIdField do
  use Ecto.Migration
  alias Pleroma.Clippy

  def change do
    Clippy.puts("ATTENTION! This migration might take hours! If you don't want to run it now, abort this with CTRL+C! I'll wait 30 seconds now.")
    :timer.sleep(:timer.seconds(30))
    execute("update objects set ap_id = data->>'id'")
    create unique_index(:objects, [:ap_id])
  end
end
