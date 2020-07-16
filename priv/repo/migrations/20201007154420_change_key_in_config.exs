defmodule Pleroma.Repo.Migrations.ChangeKeyInConfig do
  use Ecto.Migration

  import Ecto.Query

  alias Pleroma.Repo

  def up do
    alter table(:config) do
      modify(:key, :string, null: true)
    end

    create_if_not_exists(unique_index(:config, [:group, "(key is null)"], where: "key IS NULL"))
  end

  def down do
    query = from(c in "config", where: is_nil(c.key))

    if Repo.aggregate(query, :count) == 0 do
      revert()
    else
      configs = Repo.all(query)

      new_configs =
        Enum.reduce(configs, [], fn %{group: group, value: config}, group_acc ->
          Enum.reduce(config, group_acc, fn {key, value}, acc ->
            [%{group: group, key: key, value: value} | acc]
          end)
        end)

      Enum.each(new_configs, fn config ->
        {:ok, _} = Pleroma.ConfigDB.update_or_create(config)
      end)

      Enum.each(configs, &Repo.delete!(&1))

      flush()
      revert()
    end
  end

  defp revert do
    alter table(:config) do
      modify(:key, :string, null: false)
    end

    drop_if_exists(unique_index(:config, [:group, "(key is null)"]))
  end
end
