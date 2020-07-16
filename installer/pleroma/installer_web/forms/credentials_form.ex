# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.InstallerWeb.Forms.CredentialsForm do
  use Ecto.Schema

  import Ecto.Changeset

  require Logger

  @primary_key false

  embedded_schema do
    field(:username, :string)
    field(:password, :string, default: "")
    field(:database, :string)
    field(:hostname, :string)
    field(:pool_size, :integer, default: 2)
    field(:rum_enabled, :boolean, default: false)
  end

  @spec defaults() :: Ecto.Changeset.t()
  def defaults do
    env = Pleroma.Config.get(:env)

    %__MODULE__{}
    |> cast(
      %{
        username: "pleroma",
        password: "",
        database: "pleroma_#{env}",
        hostname: "localhost"
      },
      [:username, :password, :database, :hostname, :rum_enabled]
    )
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, [:username, :password, :database, :hostname, :rum_enabled])
    |> validate_required([:username, :database, :hostname, :rum_enabled])
  end

  @spec generate(Ecto.Changeset.t()) ::
          {:ok, String.t(), Ecto.Changeset.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, term()}
          | {:error, :file.posix()}
  def generate(changeset) do
    changeset =
      if get_change(changeset, :password) do
        changeset
      else
        change(changeset,
          password: :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)
        )
      end

    do_generate(changeset)
  end

  defp do_generate(changeset) do
    case apply_action(changeset, :create) do
      {:ok, struct} ->
        credentials =
          struct
          |> Map.from_struct()
          |> Map.to_list()

        result_psql =
          EEx.eval_file(
            "installer/templates/sample_psql.eex",
            credentials
          )

        psql_path =
          Pleroma.Application.config_path() |> Path.dirname() |> Path.join("setup_db.psql")

        Logger.warn("Writing the postgres script to #{psql_path}.")

        case File.write(psql_path, result_psql) do
          :ok -> {:ok, psql_path, changeset}
          error -> error
        end

      error ->
        error
    end
  end

  @spec save(Ecto.Changeset.t()) ::
          :ok
          | {:error, Ecto.Changeset.t()}
          | {:error, %DBConnection.ConnectionError{}}
          | {:error, term()}
          | {:error, :file.posix()}
  def save(changeset) do
    case apply_action(changeset, :create) do
      {:ok, struct} ->
        struct
        |> Map.from_struct()
        |> Map.to_list()
        |> do_save()

      error ->
        error
    end
  end

  defp do_save(credentials) do
    # we try to connect to default database
    {:ok, _} = Pleroma.Repo.start_link(Keyword.put(credentials, :database, "postgres"))

    with {:ok, _} <- Pleroma.Repo.query("SELECT 1"),
         :ok <- create_database(credentials),
         # we stop repo with default database and reconnect to newly created
         :ok <- Pleroma.Repo.stop(),
         {:ok, _} <- Pleroma.Repo.start_link(credentials),
         #  :ok <- create_extensions(credentials),
         :ok <- run_migrations(),
         :ok <- run_rum_migrations(credentials),
         config_path <- Pleroma.Application.config_path(),
         :ok <- write_credentials_to_config_file(credentials, config_path) do
      Pleroma.Repo.stop()

      config_path
      |> Config.Reader.read!()
      |> Application.put_all_env()
    end
  end

  defp create_database(credentials) do
    {:ok, %{rows: [[database_exists?]]}} =
      Pleroma.Repo.query(
        "select exists(SELECT datname FROM pg_catalog.pg_database WHERE lower(datname) = lower('#{
          credentials[:database]
        }'));"
      )

    if database_exists? do
      :ok
    else
      case Ecto.Adapters.Postgres.storage_up(credentials) do
        :ok ->
          :ok

        {:error, :already_up} ->
          :ok

        error ->
          Logger.error(inspect(error))
          error
      end
    end
  end

  defp run_migrations, do: Mix.Tasks.Pleroma.Ecto.Migrate.run()

  defp run_rum_migrations(credentials) do
    if credentials[:rum_enabled] do
      Mix.Tasks.Pleroma.Ecto.Migrate.run([
        "--migrations-path",
        "priv/repo/optional_migrations/rum_indexing/"
      ])
    else
      :ok
    end
  end

  defp write_credentials_to_config_file(credentials, config_path) do
    config = EEx.eval_file("installer/templates/credentials.eex", credentials)

    File.write(config_path, config)
  end
end
