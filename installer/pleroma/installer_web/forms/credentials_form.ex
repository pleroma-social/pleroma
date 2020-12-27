# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.InstallerWeb.Forms.CredentialsForm do
  use Ecto.Schema

  import Ecto.Changeset

  alias Pleroma.Config

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
    env = Config.get(:env)

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

  defp to_keyword(struct) do
    struct
    |> Map.from_struct()
    |> Map.to_list()
  end

  def check_connection_and_write_config(changeset, setup_db?) do
    if setup_db? do
      changeset
      |> setup()
      |> do_check_connection_and_write_config()
    else
      with {:ok, struct} <- apply_action(changeset, :create) do
        struct
        |> to_keyword()
        |> do_check_connection_and_write_config()
      end
    end
  end

  defp do_check_connection_and_write_config(credentials) when is_list(credentials) do
    # we try to connect to default database
    with {:ok, _} <- Pleroma.Repo.start_link(Keyword.put(credentials, :database, "postgres")),
         {:ok, _} <- Pleroma.Repo.query("SELECT 1"),
         :ok <- create_database(credentials),
         :ok <- Pleroma.Repo.stop(),
         config_path <- Pleroma.Application.config_path(),
         :ok <- write_credentials_to_config_file(credentials, config_path) do
      config_path
      |> Config.Reader.read!()
      |> Application.put_all_env()
    end
  end

  defp do_check_connection_and_write_config(result), do: result

  defp setup(changeset) do
    changeset =
      if get_change(changeset, :password) do
        changeset
      else
        change(changeset,
          password: :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)
        )
      end

    with {:ok, struct} <- apply_action(changeset, :create) do
      credentials = to_keyword(struct)

      psql =
        EEx.eval_file(
          "installer/templates/sample_psql.eex",
          credentials
        )

      case System.cmd("echo", [psql, "|", "sudo", "-Hu", "postgres", "psql"]) do
        {_, 0} ->
          credentials

        _ ->
          psql_path =
            Pleroma.Application.config_path() |> Path.dirname() |> Path.join("setup_db.psql")

          Logger.warn("Writing the postgres script to #{psql_path}.")

          case File.write(psql_path, psql) do
            :ok ->
              Config.put(:credentials_changeset, changeset)
              {:ok, psql_path}

            error ->
              error
          end
      end
    end
  end

  def migrations do
    with {:ok, _} <- Pleroma.Repo.start_link(),
         :ok <- run_migrations(),
         :ok <- run_rum_migrations() do
      Pleroma.Repo.stop()
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

  defp run_rum_migrations() do
    if Config.get([:database, :rum_enabled]) do
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
