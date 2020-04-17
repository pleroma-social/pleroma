# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Frontend.AdminControllerTest do
  use Pleroma.Web.ConnCase

  test "renders index.html from admin fe", %{conn: conn} do
    conn = get(conn, frontend_admin_path(conn, :index, []))
    assert html_response(conn, 200) =~ "test Admin Develop FE"
  end
end
