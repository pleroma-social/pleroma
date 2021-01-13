# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.InstallerWeb.Forms.CredentialsForm do
  use Ecto.Schema

  import Ecto.Changeset

  require Logger

  alias Pleroma.Config
  alias Pleroma.Repo

  @callbacks Config.get([:installer, :callbacks], Pleroma.Installer.Callbacks)

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
  def changeset(attrs \\ %{}, opts \\ []) do
    %__MODULE__{}
    |> cast(attrs, [:username, :password, :database, :hostname, :rum_enabled])
    |> maybe_add_password(opts)
    |> validate_required([:username, :database, :hostname, :rum_enabled, :password])
  end

  defp maybe_add_password(%{changes: %{password: _}} = changeset, _), do: changeset

  defp maybe_add_password(changeset, opts) do
    if opts[:generate_password] do
      generated = :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)
      change(changeset, password: generated)
    else
      changeset
    end
  end

  @spec save_credentials(Ecto.Changeset.t()) ::
          :ok | {:error, :psql_file_execution, Path.t()} | {:error, term()}
  def save_credentials(changeset) do
    with {:ok, struct} <- apply_action(changeset, :insert) do
      struct
      |> Map.from_struct()
      |> Keyword.new()
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

    with :ok <- @callbacks.write(psql_path, psql),
         {_, 0} <- @callbacks.execute_psql_file(psql_path) do
      Config.put(:credentials, credentials)
      credentials
    else
      {_, exit_status} when is_integer(exit_status) ->
        # psql file saved, but something is wrong with system call,
        # so we let the user to run it manually
        # temporarily save the credentials
        Config.put(:credentials, credentials)
        Logger.warn("Writing the postgres script to #{psql_path}.")
        {:error, :psql_file_execution, psql_path}

      error ->
        error
        |> inspect()
        |> Logger.error()

        error
    end
  end

  defp check_database_connection_and_extensions(credentials) when is_list(credentials) do
    with {:ok, _} <- @callbacks.start_dynamic_repo(credentials),
         {:ok, _} <- @callbacks.check_connection(),
         :ok <- @callbacks.check_extensions(credentials[:rum_enabled]) do
      credentials
    end
  end

  defp check_database_connection_and_extensions(error), do: error

  defp write_config_file(credentials) when is_list(credentials) do
    config_path = Pleroma.Application.config_path()

    config = EEx.eval_file("installer/templates/credentials.eex", credentials)

    with :ok <- File.write(config_path, config) do
      updated_config = Keyword.merge(Repo.config(), credentials)

      Config.put(Repo, updated_config)
      Config.put([:database, :rum_enabled], credentials[:rum_enabled])

      @repo
      |> Process.whereis()
      |> case do
        repo when is_pid(repo) -> Supervisor.stop(repo)
        _ -> :ok
      end
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

    credentials = Config.get(:credentials)

    with {:ok, _} <- @callbacks.start_dynamic_repo(credentials) do
      case @callbacks.run_migrations(paths, @repo) do
        [] -> {:error, :migration_error}
        _ -> :ok
      end
    end
  end
end
