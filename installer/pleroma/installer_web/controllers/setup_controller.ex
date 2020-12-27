# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.InstallerWeb.SetupController do
  use Pleroma.InstallerWeb, :controller

  alias Pleroma.InstallerWeb.Forms.ConfigForm
  alias Pleroma.InstallerWeb.Forms.CredentialsForm

  plug(:authenticate)

  def index(conn, _) do
    render(conn, "index.html")
  end

  def credentials(conn, params) do
    setup_db = params["setup_db"] == "true"

    conn
    |> put_session(:setup_db, setup_db)
    |> render("credentials.html",
      credentials: CredentialsForm.defaults(),
      connection_error: false,
      error: nil,
      setup_db: setup_db
    )
  end

  def save_credentials(conn, params) do
    setup_db? = get_session(conn, :setup_db)

    changeset = CredentialsForm.changeset(params["credentials_form"])

    check_connection_and_write_config(conn, changeset, setup_db?)
  end

  defp check_connection_and_write_config(conn, changeset, setup_db? \\ false) do
    case CredentialsForm.check_connection_and_write_config(changeset, setup_db?) do
      :ok ->
        redirect(conn, to: Routes.setup_path(conn, :migrations))

      {:ok, psql_path} ->
        render(conn, "run_psql.html", psql_path: psql_path)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "credentials.html",
          credentials: changeset,
          error: nil,
          setup_db: setup_db?
        )

      {:error, %DBConnection.ConnectionError{}} ->
        render(conn, "credentials.html",
          credentials: changeset,
          error:
            "Pleroma can't connect to database with these credentials. Please check them and try one more time.",
          setup_db: setup_db?
        )

      {:error, error} ->
        render(conn, "credentials.html",
          credentials: changeset,
          error: error,
          setup_db: setup_db?
        )
    end
  end

  def save_generated_credentials(conn, _) do
    changeset = Pleroma.Config.get(:credentials)
    Pleroma.Config.delete(:credentials)
    check_connection_and_write_config(conn, changeset)
  end

  def migrations(conn, _) do
    Task.start(fn -> CredentialsForm.migrations() end)
    render(conn, "migrations.html")
  end

  def run_migrations(conn, params) do
    json(conn, %{url: Routes.setup_path(conn, :config, token: params["token"])})
  end

  def config(conn, params) do
    render(conn, "config.html", config: ConfigForm.defaults(), token: params["token"])
  end

  def save_config(conn, params) do
    changeset = ConfigForm.changeset(params["config_form"])

    token = params["token"]
    Pleroma.Application.start_repo()

    case ConfigForm.save(changeset) do
      :ok ->
        Pleroma.Config.delete(:installer_token)
        Pleroma.Application.stop_installer_and_start_pleroma()

        redirect(conn, external: Pleroma.Web.Endpoint.url())

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "config.html", config: changeset, token: token)

      {:error, :config_file_not_found} ->
        render(conn, "config.html", error: :config_file_not_found, token: token)

      {:error, error} ->
        render(conn, "config.html", error: error, token: token)
    end
  end

  defp authenticate(conn, _) do
    token = Pleroma.Config.get(:installer_token)

    cond do
      get_session(conn, :token) == token ->
        conn

      conn.query_params["token"] == token ->
        put_session(conn, :token, token)

      true ->
        conn
        |> text("Token is invalid")
        |> halt()
    end
  end
end
