# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.CookieAuthPlugTest do
  use Pleroma.Web.ConnCase, async: true
  alias Pleroma.Web.Plugs.CookieAuthPlug
  import Pleroma.Factory

  @session_opts [
    store: :cookie,
    key: "_test",
    signing_salt: "cooldude"
  ]

  setup %{conn: conn} do
    conn =
      conn
      |> Plug.Session.call(Plug.Session.init(@session_opts))
      |> fetch_session()

    %{conn: conn}
  end

  test "if the conn has a user key set, it does nothing", %{conn: conn} do
    conn = assign(conn, :user, 1)
    result = CookieAuthPlug.call(conn, %{})

    assert result == conn
  end

  test "if the session has a user_id, it sets the user", %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> put_session(:user_id, user.id)
      |> CookieAuthPlug.call(%{})

    assert conn.assigns[:user] == user
  end

  test "if the conn has no key set, it does nothing", %{conn: conn} do
    result = CookieAuthPlug.call(conn, %{})

    assert result == conn
  end
end
