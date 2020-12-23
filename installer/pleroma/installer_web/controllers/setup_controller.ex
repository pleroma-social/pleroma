# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.InstallerWeb.SetupController do
  use Pleroma.InstallerWeb, :controller

  alias Pleroma.InstallerWeb.Forms.ConfigForm
  alias Pleroma.InstallerWeb.Forms.CredentialsForm

  plug(:authenticate)

  def index(conn, params) do
    render(conn, "index.html", token: params["token"])
  end

  def credentials_setup(conn, params) do
    render(conn, "credentials_setup.html",
      credentials: CredentialsForm.defaults(),
      token: params["token"],
      error: nil
    )
  end

  def create_psql_user(conn, params) do
    changeset = CredentialsForm.changeset(params["credentials_form"])

    token = params["token"]

    case CredentialsForm.create_psql_user(changeset) do
      :ok ->
        redirect(conn, to: Routes.setup_path(conn, :save_generated_credentials, token: token))

      {:ok, psql_path} ->
        render(conn, "run_psql.html", token: token, psql_path: psql_path)

      {:error, error} ->
        render(conn, "credentials_setup.html",
          credentials: changeset,
          error: error,
          token: token
        )
    end
  end

  def save_generated_credentials(conn, params) do
    changeset = Pleroma.Config.get(:db_credentials)
    Pleroma.Config.delete(:db_credentials)
    save_credentials_changeset(conn, changeset, params["token"])
  end

  def credentials(conn, params) do
    render(conn, "credentials.html",
      credentials: CredentialsForm.defaults(),
      connection_error: false,
      error: nil,
      token: params["token"]
    )
  end

  defp save_credentials_changeset(conn, changeset, token) do
    case CredentialsForm.save(changeset) do
      :ok ->
        redirect(conn, to: Routes.setup_path(conn, :config, token: token))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "credentials.html",
          credentials: changeset,
          connection_error: false,
          error: nil,
          token: token
        )

      {:error, %DBConnection.ConnectionError{}} ->
        render(conn, "credentials.html",
          credentials: changeset,
          connection_error: true,
          error: nil,
          token: token
        )

      {:error, error} ->
        render(conn, "credentials.html",
          credentials: changeset,
          error: error,
          connection_error: false,
          token: token
        )
    end
  end

  def save_credentials(conn, params) do
    changeset = CredentialsForm.changeset(params["credentials_form"])

    save_credentials_changeset(conn, changeset, params["token"])
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

    if conn.query_params["token"] == token do
      conn
    else
      conn
      |> text("Token is invalid")
      |> halt()
    end
  end
end
