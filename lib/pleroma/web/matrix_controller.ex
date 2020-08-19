# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MatrixController do
  use Pleroma.Web, :controller

  def client_versions(conn, _) do
    data = %{
      versions: ["r0.0.1", "r0.1.0", "r0.2.0", "r0.3.0", "r0.4.0", "r0.5.0"]
    }

    conn
    |> json(data)
  end

  def login_info(conn, _) do
    data = %{
      flows: [
        %{type: "m.login.password"}
      ]
    }

    conn
    |> json(data)
  end

  def login(conn, params) do
    IO.inspect(params)

    data = %{
      errcode: "M_FORBIDDEN",
      error: "Invalid password"
    }

    conn
    |> put_status(403)
    |> json(data)
  end
end
