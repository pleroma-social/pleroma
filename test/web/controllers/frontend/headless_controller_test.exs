defmodule Pleroma.Web.Frontend.HeadlessControllerTest do
  use Pleroma.Web.ConnCase

  setup do: clear_config([:frontends, :primary], %{"name" => "none", "ref" => "none"})

  test "Returns 404", %{conn: conn} do
    conn = get(conn, "/")
    assert text_response(conn, 404) == ""
  end
end
