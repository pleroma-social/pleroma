# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.MastoFEControllerTest do
  use Pleroma.Web.ConnCase

  alias Pleroma.Config
  alias Pleroma.User

  import Pleroma.Factory

  setup do: clear_config([:instance, :public])

  describe "put_settings/2" do
    setup do
      %{conn: conn, user: user} = oauth_access(["write:accounts"])
      [conn: conn, user: user]
    end

    test "common", %{conn: conn, user: user} do
      assert conn
             |> put("/api/web/settings", %{"data" => %{"programming" => "socks"}})
             |> json_response(200)

      user = User.get_cached_by_ap_id(user.ap_id)
      assert user.mastofe_settings == %{"programming" => "socks"}
    end

    test "saves notification settings", %{conn: conn, user: user} do
      assert conn
             |> put("/api/web/settings", %{
               "data" => %{
                 "notifications" => %{
                   "alerts" => %{
                     "favourite" => true,
                     "follow" => true,
                     "follow_request" => true,
                     "mention" => true,
                     "poll" => true,
                     "reblog" => true
                   },
                   "quickFilter" => %{"active" => "all", "advanced" => true, "show" => true},
                   "shows" => %{
                     "favourite" => false,
                     "follow" => false,
                     "follow_request" => false,
                     "mention" => false,
                     "poll" => false,
                     "reblog" => false
                   },
                   "sounds" => %{
                     "favourite" => true,
                     "follow" => true,
                     "follow_request" => true,
                     "mention" => true,
                     "poll" => true,
                     "reblog" => true
                   }
                 }
               }
             })

      user = User.get_cached_by_ap_id(user.ap_id)

      assert user.settings == %{
               "notifications" => %{
                 "alerts" => %{
                   "favourite" => true,
                   "follow" => true,
                   "follow_request" => true,
                   "mention" => true,
                   "poll" => true,
                   "reblog" => true
                 },
                 "quickFilter" => %{"active" => "all", "advanced" => true, "show" => true},
                 "shows" => %{
                   "favourite" => false,
                   "follow" => false,
                   "follow_request" => false,
                   "mention" => false,
                   "poll" => false,
                   "reblog" => false
                 },
                 "sounds" => %{
                   "favourite" => true,
                   "follow" => true,
                   "follow_request" => true,
                   "mention" => true,
                   "poll" => true,
                   "reblog" => true
                 }
               }
             }

      assert user.notification_settings.exclude_types == [
               "favourite",
               "follow",
               "follow_request",
               "mention",
               "poll",
               "reblog"
             ]
    end
  end

  describe "index/2 redirections" do
    setup %{conn: conn} do
      session_opts = [
        store: :cookie,
        key: "_test",
        signing_salt: "cooldude"
      ]

      conn =
        conn
        |> Plug.Session.call(Plug.Session.init(session_opts))
        |> fetch_session()

      test_path = "/web/statuses/test"
      %{conn: conn, path: test_path}
    end

    test "redirects not logged-in users to the login page", %{conn: conn, path: path} do
      conn = get(conn, path)

      assert conn.status == 302
      assert redirected_to(conn) == "/web/login"
    end

    test "redirects not logged-in users to the login page on private instances", %{
      conn: conn,
      path: path
    } do
      Config.put([:instance, :public], false)

      conn = get(conn, path)

      assert conn.status == 302
      assert redirected_to(conn) == "/web/login"
    end

    test "does not redirect logged in users to the login page", %{conn: conn, path: path} do
      token = insert(:oauth_token, scopes: ["read"])

      conn =
        conn
        |> assign(:user, token.user)
        |> assign(:token, token)
        |> get(path)

      assert conn.status == 200
    end

    test "saves referer path to session", %{conn: conn, path: path} do
      conn = get(conn, path)
      return_to = Plug.Conn.get_session(conn, :return_to)

      assert return_to == path
    end
  end
end
