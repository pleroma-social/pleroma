# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.StoreUserIpPlugTest do
  use Pleroma.Web.ConnCase, async: true
  use Plug.Test
  alias Pleroma.User
  alias Pleroma.Web.Plugs.RemoteIp
  alias Pleroma.Web.Plugs.StoreUserIpPlug
  import Pleroma.Factory

  setup do: clear_config(StoreUserIpPlug, enabled: true)

  setup do:
          clear_config(RemoteIp,
            enabled: true,
            headers: ["x-forwarded-for"],
            proxies: [],
            reserved: [
              "127.0.0.0/8",
              "::1/128",
              "fc00::/7",
              "10.0.0.0/8",
              "172.16.0.0/12",
              "192.168.0.0/16"
            ]
          )

  test "stores the user's IP address", %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> assign(:user, user)
      |> put_req_header("x-forwarded-for", "1.2.3.4")
      |> RemoteIp.call(nil)
      |> StoreUserIpPlug.call(nil)

    user = User.get_by_id(user.id)
    assert user.last_known_ip == {1, 2, 3, 4}
    assert %Plug.Conn{assigns: %{user: %User{last_known_ip: {1, 2, 3, 4}} = ^user}} = conn
  end

  test "does nothing when disabled", %{conn: conn} do
    clear_config(StoreUserIpPlug, enabled: false)
    user = insert(:user, last_known_ip: {1, 2, 3, 4})

    conn =
      conn
      |> assign(:user, user)
      |> put_req_header("x-forwarded-for", "5.4.3.2")
      |> RemoteIp.call(nil)
      |> StoreUserIpPlug.call(nil)

    assert user == User.get_by_id(user.id)
    assert %Plug.Conn{assigns: %{user: %User{last_known_ip: {1, 2, 3, 4}} = ^user}} = conn
  end
end
