# # Pleroma: A lightweight social networking server
# # Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# # SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.Environment do
  @moduledoc """
  Overwrites environment config with settings from config file or database.
  """

  require Logger

  @doc """
  Method is called on pleroma start.
  Config dependent parts don't require restart, because are not started yet.
  But started apps need restart.
  """
  @spec load_from_db_and_update() :: :ok
  def load_from_db_and_update do
    Pleroma.ConfigDB.all()
    |> update(restart_apps: true)
  end

  @spec update(Path.t()) :: :ok
  def update(config_path) when is_binary(config_path) do
    config_path
    |> Pleroma.Config.Loader.read!()
    |> Application.put_all_env()
  end

  @spec update([Pleroma.ConfigDB.t()], keyword()) :: :ok
  def update(changes, opts \\ []) when is_list(changes) do
    if Pleroma.Config.get(:configurable_from_database) do
      defaults = Pleroma.Config.Holder.default_config()

      changes
      |> filter_logger()
      |> prepare_logger_changes(defaults)
      |> Enum.each(&configure_logger/1)

      changes
      |> Pleroma.ConfigDB.merge_changes_with_defaults(defaults)
      |> Enum.each(&update_env(&1))

      if opts[:restart_apps] do
        # restart only apps on pleroma start
        changes
        |> Enum.filter(fn %{group: group} ->
          group not in [:logger, :quack, :pleroma, :prometheus, :postgrex]
        end)
        |> Pleroma.Application.ConfigDependentDeps.save_config_paths_for_restart()

        Pleroma.Application.ConfigDependentDeps.restart_dependencies()
      else
        Pleroma.Application.ConfigDependentDeps.save_config_paths_for_restart(changes)
      end
    end

    :ok
  end

  defp filter_logger(changes) do
    Enum.filter(changes, fn %{group: group} -> group in [:logger, :quack] end)
  end

  defp prepare_logger_changes(changes, defaults) do
    Enum.map(changes, fn %{group: group} = change ->
      {change, Pleroma.ConfigDB.merge_change_value_with_default(change, defaults[group])}
    end)
  end

  defp configure_logger({%{group: :quack}, merged_value}) do
    Logger.configure_backend(Quack.Logger, merged_value)
  end

  defp configure_logger({%{group: :logger} = change, merged_value}) do
    if change.value[:backends] do
      Enum.each(Application.get_env(:logger, :backends), &Logger.remove_backend/1)

      Enum.each(merged_value[:backends], &Logger.add_backend/1)
    end

    if change.value[:console] do
      console = merged_value[:console]
      console = put_in(console[:format], console[:format] <> "\n")

      Logger.configure_backend(:console, console)
    end

    if change.value[:ex_syslogger] do
      Logger.configure_backend({ExSyslogger, :ex_syslogger}, merged_value[:ex_syslogger])
    end

    Logger.configure(merged_value)
  end

  defp update_env(%{group: group, key: key, value: nil}), do: Application.delete_env(group, key)

  defp update_env(%{group: group, value: config} = change) do
    if group in Pleroma.ConfigDB.groups_without_keys() do
      Application.put_all_env([{group, config}])
    else
      Application.put_env(group, change.key, config)
    end
  end
end
