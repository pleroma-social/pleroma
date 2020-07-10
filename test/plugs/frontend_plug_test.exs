# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Plugs.FrontendPlugTest do
  use Pleroma.Web.ConnCase

  setup do: clear_config([:frontends])

  describe "setting private.frontend" do
    setup do
      conf = Pleroma.Config.get([:frontends])
      {:ok, %{conf: conf}}
    end

    test "for admin", %{conn: conn, conf: conf} do
      conn = get(conn, frontend_admin_path(conn, :index, []))
      assert get_in(conn.private, [:frontend, :config, "name"]) == conf[:admin]["name"]
    end

    test "for mastodon", %{conn: conn, conf: conf} do
      conn = get(conn, frontend_mastodon_path(conn, :index, []))
      assert get_in(conn.private, [:frontend, :config, "name"]) == conf[:mastodon]["name"]
    end

    test "for primary", %{conn: conn, conf: conf} do
      conn = get(conn, frontend_path(conn, :index_with_preload, []))
      assert get_in(conn.private, [:frontend, :config, "name"]) == conf[:primary]["name"]
    end
  end
end
