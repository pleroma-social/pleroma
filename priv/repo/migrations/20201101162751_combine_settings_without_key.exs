defmodule Pleroma.Repo.Migrations.CombineSettingsWithoutKey do
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]

  alias Pleroma.ConfigDB
  alias Pleroma.Repo

  def change do
    groups = ConfigDB.groups_without_keys()

    configs =
      from(c in ConfigDB, where: c.group in ^groups)
      |> Repo.all()

    new_configs =
      configs
      |> Enum.reduce([], fn %{group: group, key: key, value: value}, acc ->
        Keyword.update(acc, group, [{key, value}], &Keyword.merge(&1, [{key, value}]))
      end)
      |> ConfigDB.from_keyword_to_maps()

    Enum.each(new_configs, fn config ->
      {:ok, _} = ConfigDB.update_or_create(config)
    end)

    Enum.each(configs, &Repo.delete!(&1))
  end
end
