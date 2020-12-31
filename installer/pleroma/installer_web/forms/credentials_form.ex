# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.InstallerWeb.Forms.CredentialsForm do
  use Ecto.Schema

  import Ecto.Changeset

  require Logger

  alias Pleroma.Config
  alias Pleroma.Repo

  # TODO: think about naming for setting and module name
  @system Config.get([:installer, :system], Pleroma.Installer.System)
  @repo :installer_repo
  @primary_key false

  embedded_schema do
    field(:username, :string)
    field(:password, :string, default: "")
    field(:database, :string)
    field(:hostname, :string)
    field(:pool_size, :integer, default: 2)
    field(:rum_enabled, :boolean, default: false)
  end

  @spec installer_repo() :: atom()
  def installer_repo, do: @repo
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, [:username, :password, :database, :hostname, :rum_enabled])
    |> maybe_add_password()
    |> validate_required([:username, :database, :hostname, :rum_enabled, :password])
  end

  defp maybe_add_password(%{changes: %{password: _}} = changeset), do: changeset

  defp maybe_add_password(changeset) do
    generated = :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)
    change(changeset, password: generated)
  end

  @spec save_credentials(Ecto.Changeset.t()) :: :ok | {:ok, Path.t()} | {:error, term()}
  def save_credentials(changeset) do
    with {:ok, struct} <- apply_action(changeset, :insert) do
      struct
      |> Map.from_struct()
      |> Map.to_list()
      |> generate_and_save_psql_file()
      |> check_database_connection_and_extensions()
      |> write_config_file()
    end
  end

  def check_database_and_write_config do
    :credentials
    |> Config.get()
    |> check_database_connection_and_extensions()
    |> write_config_file()
  end

  defp generate_and_save_psql_file(credentials) do
    psql =
      EEx.eval_file(
        "installer/templates/sample_psql.eex",
        credentials
      )

    psql_path = "/tmp/setup_db.psql"

    with :ok <- File.write(psql_path, psql),
         {_, 0} <- @system.execute_psql_file(psql_path) do
      credentials
    else
      {_, exit_status} when is_integer(exit_status) ->
        # psql file saved, but something is wrong with system call, so we let the user to run it manually
        Config.put(:credentials, credentials)
        Logger.warn("Writing the postgres script to #{psql_path}.")
        {:ok, psql_path}

      error ->
        error
        |> inspect()
        |> Logger.error()

        error
    end
  end

  defp check_database_connection_and_extensions(credentials) when is_list(credentials) do
    config = Keyword.put(credentials, :name, @repo)

    with {:ok, repo} <- Repo.start_link(config),
         _ <- Repo.put_dynamic_repo(@repo),
         {:ok, _} <- Repo.query("SELECT 1"),
         :ok <- check_extensions(credentials[:rum_enabled]) do
      Config.put(@repo, repo)
      credentials
    end
  end

  defp check_database_connection_and_extensions(error), do: error

  defp check_extensions(rum_enabled?) do
    default = ["citext", "pg_trgm", "uuid-ossp"]

    required = if rum_enabled?, do: ["rum" | default], else: default

    with {:ok, %{rows: extensions}} <- Repo.query("SELECT pg_available_extensions();") do
      extensions = Enum.map(extensions, fn [{name, _, _}] -> name end)

      not_installed =
        Enum.reduce(required, [], fn ext, acc ->
          if ext in extensions do
            acc
          else
            [ext | acc]
          end
        end)

      if not_installed == [] do
        :ok
      else
        {:error, "These extensions are not installed: #{Enum.join(not_installed, ",")}"}
      end
    end
  end

  defp write_config_file(credentials) when is_list(credentials) do
    config_path = Pleroma.Application.config_path()

    config = EEx.eval_file("installer/templates/credentials.eex", credentials)

    with :ok <- File.write(config_path, config) do
      Config.delete(:credentials)

      updated_config = Keyword.merge(Repo.config(), credentials)

      Config.put(Repo, updated_config)
      Config.put([:database, :rum_enabled], credentials[:rum_enabled])
    end
  end

  defp write_config_file(error), do: error

  def migrations do
    path = Ecto.Migrator.migrations_path(Repo)

    paths =
      if Config.get([:database, :rum_enabled]) do
        [path, "priv/repo/optional_migrations/rum_indexing/"]
      else
        path
      end

    case Ecto.Migrator.run(Repo, paths, :up, all: true, dynamic_repo: @repo) do
      [] -> {:error, :migration_error}
      _ -> :ok
    end
  end
end
