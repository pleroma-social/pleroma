# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Config.Versioning do
  @moduledoc """
  Module that manages versions of database configs.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Pleroma.Config.Version
  alias Pleroma.ConfigDB
  alias Pleroma.Repo

  @type change :: %{
          optional(:delete) => boolean(),
          optional(:value) => any(),
          group: atom(),
          key: atom() | nil
        }

  @doc """
  Creates new config version:
    - convert changes to elixir types
    - splits changes by type and processes them in `config` table
    - sets all pointers to false
    - gets all rows from `config` table and inserts them as keyword in `backup` field
  """
  @spec new_version([change()] | change()) ::
          {:ok, map()} | {:error, :no_changes} | {:error, atom() | tuple(), any(), any()}
  def new_version([]), do: {:error, :empty_changes}
  def new_version(change) when is_map(change), do: new_version([change])

  def new_version(changes) when is_list(changes) do
    changes
    |> Enum.reduce(Multi.new(), fn
      %{delete: true} = deletion, acc ->
        Multi.run(acc, {:delete_or_update, deletion[:group], deletion[:key]}, fn _, _ ->
          ConfigDB.delete_or_update(deletion)
        end)

      operation, acc ->
        {name, fun} =
          if Keyword.keyword?(operation[:value]) or
               (operation[:group] == :pleroma and
                  operation[:key] in ConfigDB.pleroma_not_keyword_values()) do
            {:insert_or_update,
             fn _, _ ->
               ConfigDB.update_or_create(operation)
             end}
          else
            {:error,
             fn _, _ ->
               {:error, {:value_must_be_keyword, operation}}
             end}
          end

        Multi.run(acc, {name, operation[:group], operation[:key]}, fun)
    end)
    |> set_current_flag_false_for_all_versions()
    |> insert_new_version()
    |> Repo.transaction()
  end

  def new_version(_), do: {:error, :bad_format}

  defp set_current_flag_false_for_all_versions(multi) do
    Multi.update_all(multi, :update_all_versions, Version, set: [current: false])
  end

  defp insert_new_version(multi) do
    Multi.run(multi, :insert_version, fn repo, _ ->
      %Version{
        backup: ConfigDB.all_as_keyword()
      }
      |> repo.insert()
    end)
  end

  @doc """
  Rollbacks config version by N steps:
    - checks possibility for rollback
    - truncates config table and restarts pk
    - inserts config settings from backup
    - sets all pointers to false
    - sets current pointer to true for rollback version
    - deletes versions after current
  """
  @spec rollback(pos_integer()) ::
          {:ok, map()}
          | {:error, atom() | tuple(), any(), any()}
          | {:error, :steps_format}
          | {:error, :no_current_version}
          | {:error, :rollback_not_possible}
  def rollback(steps \\ 1)

  def rollback(steps) when is_integer(steps) and steps > 0 do
    with version_id when is_integer(version_id) <- get_current_version_id(),
         %Version{} = version <- get_version_by_steps(steps) do
      do_rollback(version)
    end
  end

  def rollback(_), do: {:error, :steps_format}

  @doc """
  Same as `rollback/1`, but rollbacks for a given version id.
  """
  @spec rollback_by_id(pos_integer()) ::
          {:ok, map()}
          | {:error, atom() | tuple(), any(), any()}
          | {:error, :not_found}
          | {:error, :version_is_already_current}
  def rollback_by_id(id) when is_integer(id) do
    with %Version{current: false} = version <- get_version_by_id(id) do
      do_rollback(version)
    else
      %Version{current: true} -> {:error, :version_is_already_current}
      error -> error
    end
  end

  defp get_current_version_id do
    query = from(v in Version, where: v.current == true)

    with nil <- Repo.aggregate(query, :max, :id) do
      {:error, :no_current_version}
    end
  end

  defp get_version_by_id(id) do
    with nil <- Repo.get(Version, id) do
      {:error, :not_found}
    end
  end

  defp get_version_by_steps(steps) do
    query = from(v in Version, order_by: [desc: v.id], limit: 1, offset: ^steps)

    with nil <- Repo.one(query) do
      {:error, :rollback_not_possible}
    end
  end

  defp do_rollback(version) do
    multi =
      truncate_config_table()
      |> reset_pk_in_config_table()

    version.backup
    |> ConfigDB.from_keyword_to_maps()
    |> add_insert_commands(multi)
    |> set_current_flag_false_for_all_versions()
    |> Multi.update(:move_current_pointer, Ecto.Changeset.change(version, current: true))
    |> Multi.delete_all(
      :delete_next_versions,
      from(v in Version, where: v.id > ^version.id)
    )
    |> Repo.transaction()
  end

  defp truncate_config_table(multi \\ Multi.new()) do
    Multi.run(multi, :truncate_config_table, fn repo, _ ->
      repo.query("TRUNCATE config;")
    end)
  end

  defp reset_pk_in_config_table(multi) do
    Multi.run(multi, :reset_pk, fn repo, _ ->
      repo.query("ALTER SEQUENCE config_id_seq RESTART;")
    end)
  end

  defp add_insert_commands(changes, multi) do
    Enum.reduce(changes, multi, fn change, acc ->
      Multi.run(acc, {:insert, change[:group], change[:key]}, fn _, _ ->
        ConfigDB.update_or_create(change)
      end)
    end)
  end

  @doc """
  Resets config table and creates new empty version.
  """
  @spec reset() :: {:ok, map()} | {:error, atom() | tuple(), any(), any()}
  def reset do
    truncate_config_table()
    |> reset_pk_in_config_table()
    |> set_current_flag_false_for_all_versions()
    |> insert_new_version()
    |> Repo.transaction()
  end

  @doc """
  Migrates settings from config file into database:
    - truncates config table and restarts pk
    - inserts settings from config file
    - sets all pointers to false
    - gets all rows from `config` table and inserts them as keyword in `backup` field
  """
  @spec migrate(Path.t()) :: {:ok, map()} | {:error, atom() | tuple(), any(), any()}
  def migrate(config_path) do
    multi =
      truncate_config_table()
      |> reset_pk_in_config_table()

    config_path
    |> Pleroma.Config.Loader.read!()
    |> Pleroma.Config.Loader.filter()
    |> ConfigDB.from_keyword_to_maps()
    |> add_insert_commands(multi)
    |> set_current_flag_false_for_all_versions()
    |> insert_new_version()
    |> Repo.transaction()
  end

  @doc """
  Common function to migrate old config namespace to the new one keeping the old value.
  """
  @spec migrate_namespace({atom(), atom()}, {atom(), atom()}) ::
          {:ok, map()} | {:error, atom() | tuple(), any(), any()}
  def migrate_namespace({o_group, o_key}, {n_group, n_key}) do
    config = ConfigDB.get_by_params(%{group: o_group, key: o_key})

    configs_changes_fun =
      if config do
        fn ->
          config
          |> Ecto.Changeset.change(group: n_group, key: n_key)
          |> Repo.update()
        end
      else
        fn -> {:ok, nil} end
      end

    versions_changes_fun = fn %{backup: backup} = version ->
      with {value, rest} when not is_nil(value) <- pop_in(backup[o_group][o_key]) do
        rest =
          if rest[o_group] == [] do
            Keyword.delete(rest, o_group)
          else
            rest
          end

        updated_backup =
          if Keyword.has_key?(rest, n_group) do
            put_in(rest[n_group][n_key], value)
          else
            Keyword.put(rest, n_group, [{n_key, value}])
          end

        version
        |> Ecto.Changeset.change(backup: updated_backup)
        |> Repo.update()
      else
        _ -> {:ok, nil}
      end
    end

    migrate_configs_and_versions(configs_changes_fun, versions_changes_fun)
  end

  @doc """
  Abstract function for config migrations to keep changes in config table and changes in versions backups in transaction.
  Accepts two functions:
    - first function makes changes to the configs
    - second function makes changes to the backups in versions
  """
  @spec migrate_configs_and_versions(function(), function()) ::
          {:ok, map()} | {:error, atom() | tuple(), any(), any()}
  def migrate_configs_and_versions(configs_changes_fun, version_change_fun)
      when is_function(configs_changes_fun, 0) and
             is_function(version_change_fun, 1) do
    versions = Repo.all(Version)

    multi =
      Multi.new()
      |> Multi.run(:configs_changes, fn _, _ ->
        configs_changes_fun.()
      end)

    versions
    |> Enum.reduce(multi, fn version, acc ->
      Multi.run(acc, {:version_change, version.id}, fn _, _ ->
        version_change_fun.(version)
      end)
    end)
    |> Repo.transaction()
  end
end
