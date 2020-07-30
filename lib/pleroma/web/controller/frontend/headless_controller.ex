defmodule Pleroma.Web.Frontend.HeadlessController do
  use Pleroma.Web, :controller

  def fallback(conn, _params) do
    conn
    |> put_status(404)
    |> text("")
  end
end
