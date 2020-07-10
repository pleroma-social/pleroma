# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Frontend.PleromaControllerTest do
  use Pleroma.Web.ConnCase

  import Pleroma.Factory

  test "renders index.html from pleroma fe", %{conn: conn} do
    conn = get(conn, frontend_path(conn, :index_with_preload, []))
    assert html_response(conn, 200) =~ "test Pleroma Develop FE"
  end

  test "index_with_meta", %{conn: conn} do
    user = insert(:user)

    conn = get(conn, frontend_path(conn, :index_with_meta_and_user, "nonexistinguser"))
    assert html_response(conn, 200) =~ "<!--server-generated-meta-->"

    conn = get(conn, frontend_path(conn, :index_with_meta_and_user, user.nickname))
    refute html_response(conn, 200) =~ "<!--server-generated-meta-->"
  end
end
