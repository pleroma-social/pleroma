# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.ConfigDB do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias __MODULE__
  alias Pleroma.Repo

  @type t :: %__MODULE__{}

  @full_subkey_update [
    {:pleroma, :assets, :mascots},
    {:pleroma, :emoji, :groups},
    {:pleroma, :workers, :retries},
    {:pleroma, :mrf_subchain, :match_actor},
    {:pleroma, :mrf_keyword, :replace}
  ]

  @groups_without_keys [:quack, :mime, :cors_plug, :esshd, :ex_aws, :joken, :logger, :swoosh]

  @pleroma_not_keyword_values [Pleroma.Web.Auth.Authenticator, :admin_token]

  schema "config" do
    field(:key, Pleroma.EctoType.Config.Atom)
    field(:group, Pleroma.EctoType.Config.Atom)
    field(:value, Pleroma.EctoType.Config.BinaryValue)
    field(:db, {:array, :string}, virtual: true, default: [])

    timestamps()
  end

  @spec all() :: [t()]
  def all, do: Repo.all(ConfigDB)

  @spec all_with_db() :: [t()]
  def all_with_db do
    all()
    |> Enum.map(fn
      %{group: :pleroma, key: key} = change when key in @pleroma_not_keyword_values ->
        %{change | db: [change.key]}

      %{value: value} = change ->
        %{change | db: Keyword.keys(value)}
    end)
  end

  @spec all_as_keyword() :: keyword()
  def all_as_keyword do
    all()
    |> as_keyword()
  end

  @spec as_keyword([t()]) :: keyword()
  def as_keyword(changes) do
    Enum.reduce(changes, [], fn
      %{group: group, key: nil, value: value}, acc ->
        Keyword.update(acc, group, value, &Keyword.merge(&1, value))

      %{group: group, key: key, value: value}, acc ->
        Keyword.update(acc, group, [{key, value}], &Keyword.merge(&1, [{key, value}]))
    end)
  end

  @spec get_all_by_group(atom() | String.t()) :: [t()]
  def get_all_by_group(group) do
    from(c in ConfigDB, where: c.group == ^group) |> Repo.all()
  end

  @spec get_by_group_and_key(atom() | String.t(), atom() | String.t()) :: t() | nil
  def get_by_group_and_key(group, key) do
    get_by_params(%{group: group, key: key})
  end

  @spec get_by_params(map()) :: ConfigDB.t() | nil
  def get_by_params(%{group: group, key: key} = params)
      when not is_nil(key) and not is_nil(group) do
    Repo.get_by(ConfigDB, params)
  end

  def get_by_params(%{group: group}) do
    from(c in ConfigDB, where: c.group == ^group and is_nil(c.key)) |> Repo.one()
  end

  @spec changeset(ConfigDB.t(), map()) :: Changeset.t()
  def changeset(config, params \\ %{}) do
    config
    |> cast(params, [:key, :group, :value])
    |> validate_required([:group, :value])
    |> unique_constraint(:key, name: :config_group_key_index)
    |> unique_constraint(:key, name: :config_group__key_is_null_index)
  end

  defp create(params) do
    %ConfigDB{}
    |> changeset(params)
    |> Repo.insert()
  end

  defp update(%ConfigDB{} = config, %{value: value}) do
    config
    |> changeset(%{value: value})
    |> Repo.update()
  end

  @doc """
  IMPORTANT!!!
  Before modifying records in the database directly, please read "Config versioning" in `docs/dev.md`.
  """
  @spec update_or_create(map()) :: {:ok, ConfigDB.t()} | {:error, Changeset.t()}
  def update_or_create(params) do
    search_opts = Map.take(params, [:group, :key])

    with %ConfigDB{} = config <- ConfigDB.get_by_params(search_opts) do
      new_value = merge_group(config.group, config.key, config.value, params[:value])

      update(config, %{value: new_value})
    else
      nil ->
        create(params)
    end
  end

  @doc """
  IMPORTANT!!!
  Before modifying records in the database directly, please read "Config versioning" in `docs/dev.md`.
  """
  @spec delete(ConfigDB.t() | map()) :: {:ok, ConfigDB.t()} | {:error, Changeset.t()}
  def delete(%ConfigDB{} = config), do: Repo.delete(config)

  @doc """
  IMPORTANT!!!
  Before modifying records in the database directly, please read "Config versioning" in `docs/dev.md`.
  """
  @spec delete_or_update(map()) :: {:ok, t()} | {:ok, nil} | {:error, Changeset.t()}
  def delete_or_update(%{group: _, key: key} = params) when not is_nil(key) do
    search_opts = Map.take(params, [:group, :key])

    with %ConfigDB{} = config <- ConfigDB.get_by_params(search_opts) do
      do_delete_or_update(config, params[:subkeys])
    else
      _ -> {:ok, nil}
    end
  end

  def delete_or_update(%{group: group}) do
    query = from(c in ConfigDB, where: c.group == ^group)

    with {num, _} <- Repo.delete_all(query) do
      {:ok, num}
    end
  end

  defp do_delete_or_update(%ConfigDB{} = config, subkeys)
       when is_list(subkeys) and subkeys != [] do
    new_value = Keyword.drop(config.value, subkeys)

    if new_value == [] do
      delete(config)
    else
      update(config, %{value: new_value})
    end
  end

  defp do_delete_or_update(%ConfigDB{} = config, _), do: delete(config)

  defp merge_group(group, key, old_value, new_value)
       when is_list(old_value) and is_list(new_value) do
    new_keys = to_mapset(new_value)

    intersect_keys = old_value |> to_mapset() |> MapSet.intersection(new_keys) |> MapSet.to_list()

    merged_value = deep_merge(old_value, new_value)

    @full_subkey_update
    |> Enum.reduce([], fn
      {g, k, subkey}, acc when g == group and k == key ->
        if subkey in intersect_keys do
          [subkey | acc]
        else
          acc
        end

      _, acc ->
        acc
    end)
    |> Enum.reduce(merged_value, &Keyword.put(&2, &1, new_value[&1]))
  end

  defp merge_group(_group, _key, _old_value, new_value) when is_list(new_value), do: new_value

  defp merge_group(:pleroma, key, _old_value, new_value)
       when key in @pleroma_not_keyword_values do
    new_value
  end

  defp to_mapset(keyword) when is_list(keyword) do
    keyword
    |> Keyword.keys()
    |> MapSet.new()
  end

  defp deep_merge(config1, config2) when is_list(config1) and is_list(config2) do
    Keyword.merge(config1, config2, fn _, app1, app2 ->
      if Keyword.keyword?(app1) and Keyword.keyword?(app2) do
        Keyword.merge(app1, app2, &deep_merge/3)
      else
        app2
      end
    end)
  end

  defp deep_merge(_key, value1, value2) do
    if Keyword.keyword?(value1) and Keyword.keyword?(value2) do
      Keyword.merge(value1, value2, &deep_merge/3)
    else
      value2
    end
  end

  @spec reduce_defaults_and_merge_with_changes([t()], keyword()) :: {[t()], keyword()}
  def reduce_defaults_and_merge_with_changes(changes, defaults) do
    Enum.reduce(changes, {[], defaults}, &reduce_default_and_merge_with_change/2)
  end

  defp reduce_default_and_merge_with_change(%{group: group} = change, {acc, defaults})
       when group in @groups_without_keys do
    {default, remaining_defaults} = Keyword.pop(defaults, group)

    change = merge_change_with_default(change, default)
    {[change | acc], remaining_defaults}
  end

  defp reduce_default_and_merge_with_change(%{group: group, key: key} = change, {acc, defaults}) do
    if defaults[group] do
      {default, remaining_group_defaults} = Keyword.pop(defaults[group], key)

      remaining_defaults =
        if remaining_group_defaults == [] do
          Keyword.delete(defaults, group)
        else
          Keyword.put(defaults, group, remaining_group_defaults)
        end

      change = merge_change_with_default(change, default)

      {[change | acc], remaining_defaults}
    else
      {[change | acc], defaults}
    end
  end

  @spec from_keyword_to_structs(keyword(), [] | [t()]) :: [t()]
  def from_keyword_to_structs(keyword, initial_acc \\ []) do
    Enum.reduce(keyword, initial_acc, &reduce_to_structs/2)
  end

  defp reduce_to_structs({group, config}, group_acc) when group in @groups_without_keys do
    [struct(%ConfigDB{}, to_map(group, config)) | group_acc]
  end

  defp reduce_to_structs({group, config}, group_acc) do
    Enum.reduce(config, group_acc, fn {key, value}, acc ->
      [struct(%ConfigDB{}, to_map(group, key, value)) | acc]
    end)
  end

  @spec from_keyword_to_maps(keyword(), [] | [map()]) :: [map()]
  def from_keyword_to_maps(keyword, initial_acc \\ []) do
    Enum.reduce(keyword, initial_acc, &reduce_to_maps/2)
  end

  defp reduce_to_maps({group, config}, group_acc) when group in @groups_without_keys do
    [to_map(group, config) | group_acc]
  end

  defp reduce_to_maps({group, config}, group_acc) do
    Enum.reduce(config, group_acc, fn {key, value}, acc ->
      [to_map(group, key, value) | acc]
    end)
  end

  defp to_map(group, config), do: %{group: group, value: config}

  defp to_map(group, key, value), do: %{group: group, key: key, value: value}

  @spec merge_changes_with_defaults([t()], keyword()) :: [t()]
  def merge_changes_with_defaults(changes, defaults) when is_list(changes) do
    Enum.map(changes, fn
      %{group: group} = change when group in @groups_without_keys ->
        merge_change_with_default(change, defaults[group])

      %{group: group, key: key} = change ->
        merge_change_with_default(change, defaults[group][key])
    end)
  end

  defp merge_change_with_default(change, default) do
    %{change | value: merge_change_value_with_default(change, default)}
  end

  @spec merge_change_value_with_default(t(), keyword()) :: keyword()
  def merge_change_value_with_default(change, default) do
    if Ecto.get_meta(change, :state) == :deleted do
      default
    else
      merge_group(change.group, change.key, default, change.value)
    end
  end

  @spec groups_without_keys() :: [atom()]
  def groups_without_keys, do: @groups_without_keys

  @spec pleroma_not_keyword_values() :: [atom()]
  def pleroma_not_keyword_values, do: @pleroma_not_keyword_values
end
