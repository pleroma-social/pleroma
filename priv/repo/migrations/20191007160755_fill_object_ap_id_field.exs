defmodule Pleroma.Repo.Migrations.FillObjectApIdField do
  use Ecto.Migration

  def change do
    execute("update objects set ap_id = data->>'id'")
  end
end
