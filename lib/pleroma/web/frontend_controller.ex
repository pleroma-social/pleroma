# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FrontendController do
  use Pleroma.Web, :controller
  import Pleroma.Frontend, only: [get_primary_fe_opts: 0]
  alias Pleroma.Web.Frontend.StaticController

  def action(conn, _opts) do
    # `conn.private[:frontend]` can be missing if the function is called outside
    # of the standard controller pipeline. In this case we set frontend as a
    # :primary one
    fe_config = conn.private[:frontend] || get_primary_fe_opts()

    # can only be true for :primary frontend
    static_enabled? = Map.get(fe_config, :static, false)

    action_name = action_name(conn)

    {controller, action} =
      cond do
        static_enabled? and function_exported?(StaticController, action_name, 2) ->
          {StaticController, action_name}

        function_exported?(fe_config[:controller], action_name, 2) ->
          {fe_config[:controller], action_name}

        true ->
          {fe_config[:controller], :fallback}
      end

    conn
    # in case we are serving an internal call
    |> put_private(:frontend, fe_config)
    |> put_view(Phoenix.Controller.__view__(controller))
    |> controller.call(controller.init(action))
  end
end
