defmodule Pleroma.Repo.Migrations.CreateBaseConfigVersion do
  use Ecto.Migration

  def change do
    configs = Pleroma.ConfigDB.all_as_keyword()

    unless configs == [] do
      %Pleroma.Config.Version{
        backup: configs,
        current: true
      }
      |> Pleroma.Repo.insert!()
    end
  end
end
