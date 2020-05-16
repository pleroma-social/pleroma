# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.DomainMuteController do
  use Pleroma.Web, :controller

  plug(Pleroma.Web.ApiSpec.CastAndValidate)
  defdelegate open_api_operation(action), to: Pleroma.Web.ApiSpec.DomainMuteOperation

  plug(
    Pleroma.Plugs.OAuthScopesPlug,
    %{scopes: ["follow", "read:mutes"]} when action == :index
  )

  plug(
    Pleroma.Plugs.OAuthScopesPlug,
    %{scopes: ["follow", "write:mutes"]} when action != :index
  )

  @doc "GET /api/pleroma/domain_mutes"
  def index(%{assigns: %{user: user}} = conn, _) do
    json(conn, Map.get(user, :domain_mutes, []))
  end

  @doc "POST /api/pleroma/domain_mutes"
  def create(%{assigns: %{user: user}, body_params: %{domain: domain}} = conn, _) do
    Pleroma.User.mute_domain(user, domain)
    json(conn, %{})
  end

  @doc "DELETE /api/pleroma/domain_mutes"
  def delete(%{assigns: %{user: user}, body_params: %{domain: domain}} = conn, _) do
    Pleroma.User.unmute_domain(user, domain)
    json(conn, %{})
  end
end
