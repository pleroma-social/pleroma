# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Frontend.MastodonController do
  use Pleroma.Web, :controller
  use Pleroma.Web.Frontend.DefaultController

  alias Pleroma.Plugs.OAuthScopesPlug
  alias Pleroma.User

  plug(OAuthScopesPlug, %{scopes: ["write:accounts"]} when action == :put_settings)

  # Note: :index action handles attempt of unauthenticated access to private instance with redirect
  plug(
    OAuthScopesPlug,
    %{scopes: ["read"], fallback: :proceed_unauthenticated, skip_instance_privacy_check: true}
    when action == :index
  )

  plug(
    Pleroma.Plugs.EnsurePublicOrAuthenticatedPlug
    when action != :index
  )

  def index(%{assigns: %{user: user, token: token}} = conn, _params)
      when not is_nil(user) and not is_nil(token) do
    conn
    |> put_layout(false)
    |> render("index.html",
      token: token.token,
      user: user,
      custom_emojis: Pleroma.Emoji.get_all()
    )
  end

  def index(conn, _params) do
    conn
    |> put_session(:return_to, conn.request_path)
    |> redirect(to: auth_path(conn, :login))
  end

  @doc "GET /web/manifest.json"
  def manifest(conn, _params) do
    render(conn, "manifest.json")
  end

  @doc "PUT /api/web/settings"
  def put_settings(%{assigns: %{user: user}} = conn, %{"data" => settings} = _params) do
    case User.mastodon_settings_update(user, settings) do
      {:ok, _} ->
        json(conn, %{})

      e ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(e)})
    end
  end
end
