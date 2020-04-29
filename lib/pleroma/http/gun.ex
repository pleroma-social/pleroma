# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP.Gun do
  alias Pleroma.Config

  @spec options(keyword(), URI.t()) :: keyword()
  def options(opts \\ [], %URI{} = uri) do
    merge_defaults_with_config()
    |> add_scheme_opts(uri)
    |> maybe_add_proxy()
    |> Keyword.merge(opts)
    |> add_pool_timeout()
    |> add_reuse_conn_flag()
    |> add_pool_alive_flag()
  end

  defp merge_defaults_with_config do
    config = Config.get([:http, :adapter], [])

    defaults = [
      connect_timeout: 5_000,
      domain_lookup_timeout: 5_000,
      tls_handshake_timeout: 5_000,
      retry: 1,
      retry_timeout: 1000,
      await_up_timeout: 5_000
    ]

    Keyword.merge(defaults, config)
  end

  defp add_scheme_opts(opts, %{scheme: "http"}), do: opts

  defp add_scheme_opts(opts, %{scheme: "https"}) do
    tls_opts = [
      log_level: :warning,
      session_lifetime: 6000,
      session_cache_client_max: 250
    ]

    Keyword.merge(opts, certificates_verification: true, tls_opts: tls_opts)
  end

  defp maybe_add_proxy(opts), do: Pleroma.HTTP.Proxy.maybe_add_proxy(opts)

  defp add_pool_timeout(opts) do
    default_timeout = Config.get([:pools, :default, :timeout])
    timeout = Config.get([:pools, opts[:pool], :timeout], default_timeout)
    Keyword.put(opts, :timeout, timeout)
  end

  defp add_reuse_conn_flag(opts) do
    Keyword.update(opts, :reuse_conn, true, fn flag? ->
      Pleroma.Pool.Connections.alive?(:gun_connections) and flag?
    end)
  end

  defp add_pool_alive_flag(opts) do
    pid = Process.whereis(opts[:pool])
    pool_alive? = is_pid(pid) && Process.alive?(pid)
    Keyword.put(opts, :pool_alive?, pool_alive?)
  end
end
