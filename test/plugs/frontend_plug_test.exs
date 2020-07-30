# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FrontendPlugTest do
  use Pleroma.Web.ConnCase

  test "Puts correct conn.private.frontend", %{conn: conn} do
    config = %{"name" => "sake", "ref" => "beer"}

    clear_config([:frontends, :primary], config)

    plug = Pleroma.Plugs.FrontendPlug.init(nil)
    conn = Pleroma.Plugs.FrontendPlug.call(conn, plug)

    frontend = Map.get(conn.private, :frontend, %{})

    assert frontend["controller"] == Pleroma.Web.Frontend.SakeController
    assert frontend["config"] == config
  end
end
