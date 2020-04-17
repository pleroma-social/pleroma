defmodule Pleroma.Plugs.InstanceStatic do
  @moduledoc """
  This is a shim to call `Plug.Static` but with runtime `from` configuration.

  Mountpoints are defined directly in the module to avoid calling the configuration for every request including non-static ones.

  Files in FE bundles can override files in priv/static, and files in
  instance/static can override files in FE bundles:
  instance/static > FE bundles > priv/static
  """
  @behaviour Plug

  # list of paths to be looked up in intance/static
  @instance_overridable_paths ~w(robots.txt emoji sounds images instance favicon.png packs sw.js static index.html sw-pleroma.js static-fe.css)

  # both pleroma/{STATIC_PATH} and pleroma/admin/{STATIC_PATH} can be requested
  @fe_prefixed_paths ~w(pleroma/admin pleroma)
  @fe_paths [
    # mastodon
    "packs",
    "sw.js",
    # primary frontend
    "static",
    "index.html",
    "sw-pleroma.js",
    "static-fe.css"
  ]

  def init(opts) do
    opts
    |> Keyword.put(:from, "__unconfigured_instance_static_plug")
    |> Keyword.put(:at, "/__unconfigured_instance_static_plug")
    |> Plug.Static.init()
  end

  for path <- @fe_prefixed_paths do
    def call(%{request_path: "/" <> unquote(path) <> _} = conn, opts) do
      fe_path = get_fe_path(conn)
      opts = %{opts | at: Plug.Router.Utils.split(unquote(path)), from: fe_path}

      Plug.Static.call(conn, opts)
    end
  end

  for path <- @fe_paths do
    def call(%{request_path: "/" <> unquote(path) <> _} = conn, opts) do
      fe_path = get_fe_path(conn)
      opts = %{opts | at: [], from: fe_path}

      with ^conn <- call_instance_static(conn, opts) do
        Plug.Static.call(conn, opts)
      end
    end
  end

  for path <- @instance_overridable_paths do
    def call(%{request_path: "/" <> unquote(path) <> _} = conn, opts) do
      call_instance_static(conn, opts)
    end
  end

  def call(conn, _), do: conn

  defp call_instance_static(conn, opts) do
    instance_static_path = Pleroma.Config.get([:instance, :static_dir], "instance/static")
    opts = %{opts | at: [], from: instance_static_path}
    Plug.Static.call(conn, opts)
  end

  defp get_fe_path(%{private: %{frontend: %{config: conf}}}) do
    instance_static_path = Pleroma.Config.get([:instance, :static_dir], "instance/static")
    Path.join([instance_static_path, "frontends", conf["name"], conf["ref"]])
  end
end
