# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.RuntimeStaticPlugTest do
  use Pleroma.Web.ConnCase

  @dir "test/tmp/instance_static"
  @primary_fe %{"name" => "pleroma", "ref" => "1.2.3"}
  @fe_dir Path.join([@dir, "frontends", @primary_fe["name"], @primary_fe["ref"]])

  setup do
    frontend_dir = Path.join([@dir, "frontends", @primary_fe["name"], @primary_fe["ref"]])

    frontend_dir
    |> Path.join("static")
    |> File.mkdir_p!()

    frontend_dir
    |> Path.join("index.html")
    |> File.write!("<html></html>")

    [@dir, "static"]
    |> Path.join()
    |> File.mkdir!()

    on_exit(fn -> File.rm_rf(@dir) end)
    clear_config([:instance, :static_dir], @dir)
    clear_config([:frontends, :primary], @primary_fe)
  end

  test "frontend files override files in priv" do
    content = "body{ color: red; }"

    conn = get(build_conn(), "/static-fe.css")
    refute response(conn, 200) == content

    [@fe_dir, "static-fe.css"]
    |> Path.join()
    |> File.write!(content)

    conn = get(build_conn(), "/static-fe.css")
    assert response(conn, 200) == content
  end

  test "files in instance/static overrides priv/static" do
    content = "no room for Bender"

    conn = get(build_conn(), "/robots.txt")
    refute text_response(conn, 200) == content

    [@dir, "robots.txt"]
    |> Path.join()
    |> File.write!(content)

    conn = get(build_conn(), "/robots.txt")
    assert text_response(conn, 200) == content
  end

  test "files in instance/static overrides frontend files" do
    [@fe_dir, "static", "helo.html"]
    |> Path.join()
    |> File.write!("cofe")

    conn = get(build_conn(), "/static/helo.html")
    assert html_response(conn, 200) == "cofe"

    [@dir, "static", "helo.html"]
    |> Path.join()
    |> File.write!("moto")

    conn = get(build_conn(), "/static/helo.html")
    assert html_response(conn, 200) == "moto"
  end
end
