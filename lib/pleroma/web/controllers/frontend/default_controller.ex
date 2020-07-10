# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Frontend.DefaultController do
  defmacro __using__(_opts) do
    quote do
      import Pleroma.Frontend, only: [fe_file_path: 1, fe_file_path: 2]

      def index(conn, _params) do
        status = conn.status || 200

        {:ok, index_file_path} = fe_file_path("index.html", conn.private[:frontend][:config])

        conn
        |> put_resp_content_type("text/html")
        |> send_file(status, index_file_path)
      end

      def api_not_implemented(conn, _params) do
        conn
        |> put_status(404)
        |> json(%{error: "Not implemented"})
      end

      def empty(conn, _params) do
        conn
        |> put_status(204)
        |> text("")
      end

      def fallback(conn, _params) do
        conn
        |> put_status(404)
        |> text("Not found")
      end

      defoverridable index: 2, api_not_implemented: 2, empty: 2, fallback: 2
    end
  end
end
