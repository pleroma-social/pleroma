defmodule Pleroma.Web.Frontend.HeadlessController do
  use Pleroma.Web, :controller

  def index(conn, _params) do
    conn
    |> put_status(404)
    |> text("")
  end
end
