# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Frontend.HeadlessControllerTest do
  use Pleroma.Web.ConnCase

  setup do: clear_config([:frontends, :primary])

  test "Returns 404", %{conn: conn} do
    Pleroma.Config.put([:frontends, :primary], %{"name" => "none", "ref" => ""})

    conn = get(conn, frontend_path(conn, :index_with_preload, []))
    assert text_response(conn, 404) == ""
  end
end
