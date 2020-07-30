defmodule Pleroma.Plugs.FrontendPlug do
  import Plug.Conn

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    put_private(conn, :frontend, Pleroma.Frontend.get_config())
  end
end
