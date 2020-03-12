# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Plugs.InstanceStatic do
  @moduledoc """
  This is a shim to call `Plug.Static` but with runtime `from` configuration.

  Mountpoints are defined directly in the module to avoid calling the configuration for every request including non-static ones.
  """
  @behaviour Plug

  alias Pleroma.Config

  def file_path(path) do
    instance_path = Path.join(Config.get([:instance, :static_dir], "instance/static/"), path)

    frontends_path =
      Config.get([:instance, :frontends_dir], "instance/frontends/")
      |> Path.join("pleroma-fe")
      |> Path.join(path)

    cond do
      File.exists?(instance_path) -> instance_path
      File.exists?(frontends_path) -> frontends_path
      true -> Path.join(Application.app_dir(:pleroma, "priv/static/"), path)
    end
  end

  @only ~w(index.html robots.txt static emoji packs sounds images instance favicon.png sw.js
  sw-pleroma.js fontello)

  def init(opts) do
    opts
    |> Keyword.put(:from, "__unconfigured_instance_static_plug")
    |> Keyword.put(:at, "/__unconfigured_instance_static_plug")
    |> Plug.Static.init()
  end

  for only <- @only do
    at = Plug.Router.Utils.split("/")

    def call(%{request_path: "/" <> unquote(only) <> _} = conn, opts) do
      call_static(
        conn,
        opts,
        unquote(at)
      )
    end
  end

  def call(conn, _) do
    conn
  end

  defp call_static(conn, opts, at) do
    static_dir = Config.get([:instance, :static_dir], "instance/static/")

    frontend_dir =
      Config.get([:instance, :frontends_dir], "instance/frontends/")
      |> Path.join("pleroma-fe")

    from =
      if File.exists?(Path.join(static_dir, conn.request_path)) do
        static_dir
      else
        frontend_dir
      end

    opts =
      opts
      |> Map.put(:from, from)
      |> Map.put(:at, at)

    Plug.Static.call(conn, opts)
  end
end
