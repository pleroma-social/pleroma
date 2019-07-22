defmodule Pleroma.Repo.Migrations.DropThreadVisibilityFunction do
  use Ecto.Migration
  @disable_ddl_transaction true

  def change do
    execute("drop function if exists thread_visibility(actor varchar, activity_id varchar)")
  end
end
