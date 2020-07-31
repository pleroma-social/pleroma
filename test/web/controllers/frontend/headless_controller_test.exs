# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Frontend.HeadlessControllerTest do
  use Pleroma.Web.ConnCase

  setup do: clear_config([:frontends, :primary], %{"name" => "none", "ref" => "none"})

  test "Returns 404", %{conn: conn} do
    conn = get(conn, "/")
    assert text_response(conn, 404) == ""
  end
end
