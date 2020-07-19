# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Plugs.EnsureUserKeyPlugTest do
  use Pleroma.Web.ConnCase, async: true
  alias Pleroma.Plugs.EnsureUserKeyPlug
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
    conn =
      conn
      |> assign(:user, 1)

    ret_conn =
      conn
      |> EnsureUserKeyPlug.call(%{})

    assert conn == ret_conn
  end

  test "if the session has a user_id, it sets the user", %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> put_session(:user_id, user.id)
      |> EnsureUserKeyPlug.call(%{})

    assert conn.assigns[:user] == user
  end

  test "if the conn has no key set, it sets it to nil", %{conn: conn} do
    conn =
      conn
      |> EnsureUserKeyPlug.call(%{})

    assert Map.has_key?(conn.assigns, :user)
  end
end
