# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Plugs.StaticFEPlug do
  import Plug.Conn

  def init(options), do: options

  def call(%{private: %{frontend: %{static: true}}} = conn, _) do
    action = Phoenix.Controller.action_name(conn)

    if accepts_html?(conn) and
         function_exported?(Pleroma.Web.Frontend.StaticController, action, 2) do
      conn
      |> Pleroma.Web.FrontendController.call(action)
      |> halt()
    else
      conn
    end
  end

  def call(conn, _), do: conn

  defp accepts_html?(conn) do
    case get_req_header(conn, "accept") do
      [accept | _] -> String.contains?(accept, "text/html")
      _ -> false
    end
  end
end
