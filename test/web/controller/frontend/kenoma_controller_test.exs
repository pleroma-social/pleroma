# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Frontend.KenomaControllerTest do
  use Pleroma.Web.ConnCase

  setup do: clear_config([:frontends, :primary])

  test "renders index.html from kenoma fe", %{conn: conn} do
    Pleroma.Config.put([:frontends, :primary], %{"name" => "kenoma", "ref" => "develop"})

    conn = get(conn, frontend_path(conn, :index_with_preload, []))
    assert html_response(conn, 200) =~ "test Kenoma Develop FE"
  end
end
