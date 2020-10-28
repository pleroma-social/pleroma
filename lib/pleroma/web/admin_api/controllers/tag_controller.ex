# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.AdminAPI.TagController do
  use Pleroma.Web, :controller

  import Pleroma.Web.ControllerHelper, only: [json_response: 3]

  alias Pleroma.ModerationLog
  alias Pleroma.User
  alias Pleroma.Web.AdminAPI
  alias Pleroma.Web.ApiSpec
  alias Pleroma.Web.Plugs.OAuthScopesPlug

  plug(
    OAuthScopesPlug,
    %{scopes: ["write:accounts"], admin: true} when action in [:tag, :untag]
  )

  plug(
    OAuthScopesPlug,
    %{scopes: ["read:accounts"], admin: true} when action in [:list]
  )

  plug(ApiSpec.CastAndValidate)

  action_fallback(AdminAPI.FallbackController)

  defdelegate open_api_operation(action), to: ApiSpec.Admin.TagOperation

  def list(%{assigns: %{user: _admin}} = conn, _) do
    tags = Pleroma.Tag.list_tags()

    json(conn, tags)
  end

  def tag(%{assigns: %{user: admin}} = conn, %{nicknames: nicknames, tags: tags}) do
    with {:ok, _} <- User.tag(nicknames, tags) do
      ModerationLog.insert_log(%{
        actor: admin,
        nicknames: nicknames,
        tags: tags,
        action: "tag"
      })

      json_response(conn, :no_content, "")
    end
  end

  def untag(%{assigns: %{user: admin}} = conn, %{nicknames: nicknames, tags: tags}) do
    with {:ok, _} <- User.untag(nicknames, tags) do
      ModerationLog.insert_log(%{
        actor: admin,
        nicknames: nicknames,
        tags: tags,
        action: "untag"
      })

      json_response(conn, :no_content, "")
    end
  end
end
