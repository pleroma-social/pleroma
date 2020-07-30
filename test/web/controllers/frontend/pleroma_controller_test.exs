defmodule Pleroma.Web.Frontend.PleromaControllerTest do
  use Pleroma.Web.ConnCase
  import Pleroma.Factory

  test "GET /pleroma/admin -> /pleroma/admin/", %{conn: conn} do
    assert redirected_to(get(conn, "/pleroma/admin")) =~ "/pleroma/admin/"
  end

  describe "neither preloaded data nor metadata attached to" do
    test "GET /registration/:token", %{conn: conn} do
      response = get(conn, frontend_path(conn, :registration_page, "foo"))

      assert html_response(response, 200) =~ "<!--server-generated-meta-->"
    end

    test "GET /*path", %{conn: conn} do
      assert conn
             |> get("/foo")
             |> html_response(200) =~ "<!--server-generated-meta-->"
    end
  end

  describe "preloaded data and metadata attached to" do
    test "GET /:maybe_nickname_or_id", %{conn: conn} do
      user = insert(:user)
      user_missing = get(conn, frontend_path(conn, :index_with_meta, "foo"))
      user_present = get(conn, frontend_path(conn, :index_with_meta, user.nickname))

      assert(html_response(user_missing, 200) =~ "<!--server-generated-meta-->")
      refute html_response(user_present, 200) =~ "<!--server-generated-meta-->"
      assert html_response(user_present, 200) =~ "initial-results"
    end

    test "GET /*path", %{conn: conn} do
      assert conn
             |> get("/foo")
             |> html_response(200) =~ "<!--server-generated-meta-->"

      refute conn
             |> get("/foo/bar")
             |> html_response(200) =~ "<!--server-generated-meta-->"
    end
  end

  describe "preloaded data is attached to" do
    test "GET /main/public", %{conn: conn} do
      public_page = get(conn, "/main/public")

      refute html_response(public_page, 200) =~ "<!--server-generated-meta-->"
      assert html_response(public_page, 200) =~ "initial-results"
    end

    test "GET /main/all", %{conn: conn} do
      public_page = get(conn, "/main/all")

      refute html_response(public_page, 200) =~ "<!--server-generated-meta-->"
      assert html_response(public_page, 200) =~ "initial-results"
    end
  end

  test "GET /api*path", %{conn: conn} do
    assert conn
           |> get("/api/foo")
           |> json_response(404) == %{"error" => "Not implemented"}
  end

  test "OPTIONS /*path", %{conn: conn} do
    assert conn
           |> options("/foo")
           |> response(204) == ""

    assert conn
           |> options("/foo/bar")
           |> response(204) == ""
  end
end
