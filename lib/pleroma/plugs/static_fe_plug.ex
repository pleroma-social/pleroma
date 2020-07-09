# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Plugs.StaticFEPlug do
  import Plug.Conn

  def init(options), do: options

  def call(%{private: %{frontend: %{static: true}}} = conn, _) do
    action = Phoenix.Controller.action_name(conn)

    if requires_html?(conn) and has_action?(action) do
      conn
      |> Pleroma.Web.FrontendController.call(action)
      |> halt()
    else
      conn
    end
  end

  def call(conn, _), do: conn

  defp requires_html?(conn), do: Phoenix.Controller.get_format(conn) == "html"

  defp has_action?(action),
    do: function_exported?(Pleroma.Web.Frontend.StaticController, action, 2)
end
