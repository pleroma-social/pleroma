# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.Config do
  use Mix.Task

  import Ecto.Query
  import Mix.Pleroma

  alias Pleroma.ConfigDB
  alias Pleroma.Repo

  @shortdoc "Manages the location of the config"
  @moduledoc File.read!("docs/administration/CLI_tasks/config.md")

  def run(["migrate_to_db" | options]) do
    check_configdb(fn ->
      start_pleroma()

      {opts, _} = OptionParser.parse!(options, strict: [config: :string])

      migrate_to_db(opts)
    end)
  end

  def run(["migrate_from_db" | options]) do
    check_configdb(fn ->
      start_pleroma()

      {opts, _} =
        OptionParser.parse!(options,
          strict: [env: :string, delete: :boolean],
          aliases: [d: :delete]
        )

      migrate_from_db(opts)
    end)
  end

  def run(["dump"]) do
    check_configdb(fn ->
      start_pleroma()

      settings =
        ConfigDB
        |> Repo.all()
        |> Enum.sort()

      unless settings == [] do
        shell_info("#{Pleroma.Config.Loader.config_header()}")

        Enum.each(settings, &dump(&1))
      else
        shell_error("No settings in ConfigDB.")
      end
    end)
  end

  def run(["dump", group, key]) do
    check_configdb(fn ->
      start_pleroma()

      group = maybe_atomize(group)
      key = maybe_atomize(key)

      group
      |> ConfigDB.get_by_group_and_key(key)
      |> dump()
    end)
  end

  def run(["dump", group]) do
    check_configdb(fn ->
      start_pleroma()

      group
      |> maybe_atomize()
      |> ConfigDB.get_all_by_group()
      |> Enum.each(&dump/1)
    end)
  end

  def run(["groups"]) do
    check_configdb(fn ->
      start_pleroma()

      groups =
        ConfigDB
        |> distinct([c], true)
        |> select([c], c.group)
        |> Repo.all()

      if length(groups) > 0 do
        shell_info("The following configuration groups are set in ConfigDB:\r\n")
        groups |> Enum.each(fn x -> shell_info("-  #{x}") end)
        shell_info("\r\n")
      end
    end)
  end

  def run(["reset", "--force"]) do
    check_configdb(fn ->
      start_pleroma()
      Pleroma.Config.Versioning.reset()
      shell_info("The ConfigDB settings have been removed from the database.")
    end)
  end

  def run(["reset"]) do
    check_configdb(fn ->
      start_pleroma()

      shell_info("The following settings will be permanently removed:")

      ConfigDB
      |> Repo.all()
      |> Enum.sort()
      |> Enum.each(&dump(&1))

      shell_error("\nTHIS CANNOT BE UNDONE!")

      if shell_prompt("Are you sure you want to continue?", "n") in ~w(Yn Y y) do
        Pleroma.Config.Versioning.reset()

        shell_info("The ConfigDB settings have been removed from the database.")
      else
        shell_error("No changes made.")
      end
    end)
  end

  def run(["delete", "--force", group, key]) do
    start_pleroma()

    group = maybe_atomize(group)
    key = maybe_atomize(key)

    config = ConfigDB.get_by_group_and_key(group, key)

    if not is_nil(config) do
      shell_info("The following settings will be removed from ConfigDB:\n")

      dump(config)

      Pleroma.Config.Versioning.new_version(%{group: config.group, key: config.key, delete: true})
    else
      shell_error("No settings in ConfigDB for #{inspect(group)}, #{inspect(key)}. Aborting.")
    end
  end

  def run(["delete", "--force", group]) do
    start_pleroma()

    group = maybe_atomize(group)

    configs = ConfigDB.get_all_by_group(group)

    if configs != [] do
      shell_info("The following settings will be removed from ConfigDB:\n")
      Enum.each(configs, &dump/1)
      Pleroma.Config.Versioning.new_version(%{group: group, key: nil, delete: true})
    else
      shell_error("No settings in ConfigDB for #{inspect(group)}. Aborting.")
    end
  end

  def run(["delete", group, key]) do
    start_pleroma()

    group = maybe_atomize(group)
    key = maybe_atomize(key)

    config = ConfigDB.get_by_group_and_key(group, key)

    if not is_nil(config) do
      shell_info("The following settings will be removed from ConfigDB:\n")

      dump(config)

      if shell_prompt("Are you sure you want to continue?", "n") in ~w(Yn Y y) do
        Pleroma.Config.Versioning.new_version(%{
          group: config.group,
          key: config.key,
          delete: true
        })
      else
        shell_error("No changes made.")
      end
    else
      shell_error("No settings in ConfigDB for #{inspect(group)}, #{inspect(key)}. Aborting.")
    end
  end

  def run(["delete", group]) do
    start_pleroma()

    group = maybe_atomize(group)

    configs = ConfigDB.get_all_by_group(group)

    if configs != [] do
      shell_info("The following settings will be removed from ConfigDB:\n")
      Enum.each(configs, &dump/1)

      if shell_prompt("Are you sure you want to continue?", "n") in ~w(Yn Y y) do
        Pleroma.Config.Versioning.new_version(%{group: group, key: nil, delete: true})
      else
        shell_error("No changes made.")
      end
    else
      shell_error("No settings in ConfigDB for #{inspect(group)}. Aborting.")
    end
  end

  def run(["rollback" | options]) do
    check_configdb(fn ->
      start_pleroma()
      {opts, _} = OptionParser.parse!(options, strict: [steps: :integer], aliases: [s: :steps])

      do_rollback(opts)
    end)
  end

  defp do_rollback(opts) do
    steps = opts[:steps] || 1

    case Pleroma.Config.Versioning.rollback(steps) do
      {:ok, _} ->
        shell_info("Success rollback")

      {:error, :no_current_version} ->
        shell_error("No version to rollback")

      {:error, :rollback_not_possible} ->
        shell_error("Rollback not possible. Incorrect steps value.")

      {:error, _, _, _} ->
        shell_error("Problem with backup. Rollback not possible.")

      error ->
        shell_error("error occuried: #{inspect(error)}")
    end
  end

  defp migrate_to_db(opts) do
    with :ok <- Pleroma.Config.DeprecationWarnings.warn() do
      config_file = opts[:config] || Pleroma.Application.config_path()

      if File.exists?(config_file) do
        do_migrate_to_db(config_file)
      else
        shell_info("To migrate settings, you must define custom settings in #{config_file}.")
      end
    else
      _ ->
        shell_error("Migration is not allowed until all deprecation warnings have been resolved.")
    end
  end

  defp do_migrate_to_db(config_file) do
    shell_info("Migrating settings from file: #{Path.expand(config_file)}")
    {:ok, _} = Pleroma.Config.Versioning.migrate(config_file)
    shell_info("Settings migrated.")
  end

  defp migrate_from_db(opts) do
    env = opts[:env] || Pleroma.Config.get(:env)

    config_path =
      if Pleroma.Config.get(:release) do
        :config_path
        |> Pleroma.Config.get()
        |> Path.dirname()
      else
        "config"
      end
      |> Path.join("#{env}.exported_from_db.secret.exs")

    file = File.open!(config_path, [:write, :utf8])
    IO.write(file, Pleroma.Config.Loader.config_header())

    changes =
      ConfigDB
      |> Repo.all()
      |> Enum.reduce([], fn %{group: group} = config, acc ->
        group_str = inspect(group)
        value = inspect(config.value, limit: :infinity)

        msg =
          if group in ConfigDB.groups_without_keys() do
            IO.write(file, "config #{group_str}, #{value}\r\n\r\n")
            "config #{group_str} was deleted."
          else
            key_str = inspect(config.key)
            IO.write(file, "config #{group_str}, #{key_str}, #{value}\r\n\r\n")
            "config #{group_str}, #{key_str} was deleted."
          end

        if opts[:delete] do
          shell_info(msg)

          change =
            config
            |> Map.take([:group, :key])
            |> Map.put(:delete, true)

          [change | acc]
        else
          acc
        end
      end)

    if opts[:delete] and changes != [] do
      Pleroma.Config.Versioning.new_version(changes)
    end

    :ok = File.close(file)
    System.cmd("mix", ["format", config_path])

    shell_info(
      "Database configuration settings have been exported to config/#{env}.exported_from_db.secret.exs"
    )
  end

  defp dump(%ConfigDB{} = config) do
    value = inspect(config.value, limit: :infinity)

    shell_info("config #{inspect(config.group)}, #{inspect(config.key)}, #{value}\r\n\r\n")
  end

  defp dump(_), do: :noop

  defp maybe_atomize(arg) when is_atom(arg), do: arg

  defp maybe_atomize(":" <> arg), do: maybe_atomize(arg)

  defp maybe_atomize(arg) when is_binary(arg) do
    if Pleroma.Config.Converter.module_name?(arg) do
      String.to_existing_atom("Elixir." <> arg)
    else
      String.to_atom(arg)
    end
  end

  defp check_configdb(callback) do
    with true <- Pleroma.Config.get([:configurable_from_database]) do
      callback.()
    else
      _ ->
        shell_error(
          "ConfigDB not enabled. Please check the value of :configurable_from_database in your configuration."
        )
    end
  end
end
