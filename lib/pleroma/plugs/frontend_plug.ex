# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Plugs.FrontendPlug do
  @moduledoc """
  Sets private key `:frontend` for the given connection.
  It is set to one of admin|mastodon|primary frontends config values based
  on `conn.request_path`
  """

  import Plug.Conn

  @behaviour Plug

  @mastodon_paths ~w(web packs sw.js api/web)
  @admin_paths ~w(pleroma)

  def init(opts) do
    opts
  end

  for path <- @mastodon_paths do
    def call(%{request_path: "/" <> unquote(path) <> _rest} = conn, _opts) do
      fe_config =
        Pleroma.Config.get([:frontends], %{mastodon: %{"name" => "mastodon", "ref" => ""}})

      put_private(conn, :frontend, %{
        config: fe_config[:mastodon],
        controller: Pleroma.Web.Frontend.MastodonController,
        static: false
      })
    end
  end

  for path <- @admin_paths do
    def call(%{request_path: "/" <> unquote(path) <> _rest} = conn, _opts) do
      fe_config = Pleroma.Config.get([:frontends], %{admin: %{"name" => "admin", "ref" => ""}})

      put_private(conn, :frontend, %{
        config: fe_config[:admin],
        controller: Pleroma.Web.Frontend.AdminController,
        static: false
      })
    end
  end

  def call(conn, _opts) do
    put_private(conn, :frontend, Pleroma.Frontend.get_primary_fe_opts())
  end
end
