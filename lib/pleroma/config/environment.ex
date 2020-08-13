# # Pleroma: A lightweight social networking server
# # Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# # SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Config.Environment do
  require Logger

  @spec load_and_update([ConfigDB.t()]) :: :ok
  def load_and_update(deleted_settings \\ []) do
    if Pleroma.Config.get(:configurable_from_database) do
      # We need to restart applications for loaded settings take effect

      {logger_settings, settings} =
        Pleroma.ConfigDB.load_and_merge_with_defaults(deleted_settings)
        |> Enum.split_with(fn {group, _, _, _} -> group in [:logger, :quack] end)

      logger_settings
      |> Enum.sort()
      |> Enum.each(&configure_logger/1)

      started_applications = Application.started_applications()

      settings
      |> Enum.map(&update/1)
      |> Enum.uniq()
      |> Enum.reject(&(&1 in [nil, :prometheus, :postgrex]))
      |> Enum.each(&restart(started_applications, &1))
    end

    :ok
  end

  # change logger configuration in runtime, without restart
  defp configure_logger({:quack, key, _, merged}) do
    Logger.configure_backend(Quack.Logger, [{key, merged}])
    update(:quack, key, merged)
  end

  defp configure_logger({_, :backends, _, merged}) do
    # removing current backends
    Enum.each(Application.get_env(:logger, :backends), &Logger.remove_backend/1)

    Enum.each(merged, &Logger.add_backend/1)

    update(:logger, :backends, merged)
  end

  defp configure_logger({_, key, _, merged}) when key in [:console, :ex_syslogger] do
    merged =
      if key == :console do
        put_in(merged[:format], merged[:format] <> "\n")
      else
        merged
      end

    backend =
      if key == :ex_syslogger,
        do: {ExSyslogger, :ex_syslogger},
        else: key

    Logger.configure_backend(backend, merged)
    update(:logger, key, merged)
  end

  defp configure_logger({_, key, _, merged}) do
    Logger.configure([{key, merged}])
    update(:logger, key, merged)
  end

  defp update({group, key, value, merged}) do
    update(group, key, merged)
    if group != :pleroma, do: group
  rescue
    error ->
      error_msg =
        "updating env causes error, group: #{inspect(group)}, key: #{inspect(key)}, value: #{
          inspect(value)
        } error: #{inspect(error)}"

      Logger.warn(error_msg)

      nil
  end

  defp update(group, key, nil), do: Application.delete_env(group, key)
  defp update(group, key, value), do: Application.put_env(group, key, value)

  defp restart(started_applications, app) do
    with {^app, _, _} <- List.keyfind(started_applications, app, 0),
         :ok <- Application.stop(app),
         :ok <- Application.start(app) do
      :ok
    else
      nil ->
        Logger.info("#{app} is not started.")

      error ->
        error
        |> inspect()
        |> Logger.warn()
    end
  end
end
