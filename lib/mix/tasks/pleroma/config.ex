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

      group = maybe_atomize(group)

      dump_group(group)
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
      truncatedb()
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
        truncatedb()

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

    with true <- key_exists?(group, key) do
      shell_info("The following settings will be removed from ConfigDB:\n")

      group
      |> ConfigDB.get_by_group_and_key(key)
      |> dump()

      delete_key(group, key)
    else
      _ ->
        shell_error("No settings in ConfigDB for #{inspect(group)}, #{inspect(key)}. Aborting.")
    end
  end

  def run(["delete", "--force", group]) do
    start_pleroma()

    group = maybe_atomize(group)

    with true <- group_exists?(group) do
      shell_info("The following settings will be removed from ConfigDB:\n")
      dump_group(group)
      delete_group(group)
    else
      _ -> shell_error("No settings in ConfigDB for #{inspect(group)}. Aborting.")
    end
  end

  def run(["delete", group, key]) do
    start_pleroma()

    group = maybe_atomize(group)
    key = maybe_atomize(key)

    with true <- key_exists?(group, key) do
      shell_info("The following settings will be removed from ConfigDB:\n")

      group
      |> ConfigDB.get_by_group_and_key(key)
      |> dump()

      if shell_prompt("Are you sure you want to continue?", "n") in ~w(Yn Y y) do
        delete_key(group, key)
      else
        shell_error("No changes made.")
      end
    else
      _ ->
        shell_error("No settings in ConfigDB for #{inspect(group)}, #{inspect(key)}. Aborting.")
    end
  end

  def run(["delete", group]) do
    start_pleroma()

    group = maybe_atomize(group)

    with true <- group_exists?(group) do
      shell_info("The following settings will be removed from ConfigDB:\n")
      dump_group(group)

      if shell_prompt("Are you sure you want to continue?", "n") in ~w(Yn Y y) do
        delete_group(group)
      else
        shell_error("No changes made.")
      end
    else
      _ -> shell_error("No settings in ConfigDB for #{inspect(group)}. Aborting.")
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

    ConfigDB
    |> Repo.all()
    |> Enum.each(&write_and_delete(&1, file, opts[:delete]))

    :ok = File.close(file)
    System.cmd("mix", ["format", config_path])

    shell_info(
      "Database configuration settings have been exported to config/#{env}.exported_from_db.secret.exs"
    )
  end

  defp write_and_delete(config, file, delete?) do
    config
    |> write(file)
    |> delete(delete?)
  end

  defp write(config, file) do
    value = inspect(config.value, limit: :infinity)

    IO.write(file, "config #{inspect(config.group)}, #{inspect(config.key)}, #{value}\r\n\r\n")

    config
  end

  defp delete(config, true) do
    {:ok, _} = Repo.delete(config)

    shell_info(
      "config #{inspect(config.group)}, #{inspect(config.key)} was deleted from the ConfigDB."
    )
  end

  defp delete(_config, _), do: :ok

  defp dump(%ConfigDB{} = config) do
    value = inspect(config.value, limit: :infinity)

    shell_info("config #{inspect(config.group)}, #{inspect(config.key)}, #{value}\r\n\r\n")
  end

  defp dump(_), do: :noop

  defp dump_group(group) when is_atom(group) do
    group
    |> ConfigDB.get_all_by_group()
    |> Enum.each(&dump/1)
  end

  defp group_exists?(group) do
    group
    |> ConfigDB.get_all_by_group()
    |> Enum.any?()
  end

  defp key_exists?(group, key) do
    group
    |> ConfigDB.get_by_group_and_key(key)
    |> is_nil
    |> Kernel.!()
  end

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

  defp delete_key(group, key) do
    check_configdb(fn ->
      %{group: group, key: key}
      |> ConfigDB.get_by_params()
      |> ConfigDB.delete()
    end)
  end

  defp delete_group(group) do
    check_configdb(fn ->
      group
      |> ConfigDB.get_all_by_group()
      |> Enum.each(&ConfigDB.delete/1)
    end)
  end

  defp truncatedb do
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE config;")
    Ecto.Adapters.SQL.query!(Repo, "ALTER SEQUENCE config_id_seq RESTART;")
  end
end
