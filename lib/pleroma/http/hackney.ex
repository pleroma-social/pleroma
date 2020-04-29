# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP.Hackney do
  @spec options(keyword(), URI.t()) :: keyword()
  def options(opts \\ [], %URI{} = uri) do
    merge_defaults_with_config()
    |> add_scheme_opts(uri)
    |> maybe_add_proxy()
    |> merge_with_incoming_opts(opts)
    |> add_pool_timeout()
  end

  defp merge_defaults_with_config do
    config = Pleroma.Config.get([:http, :adapter], [])

    defaults = [
      connect_timeout: 10_000,
      recv_timeout: 20_000,
      follow_redirect: true,
      force_redirect: true
    ]

    Keyword.merge(defaults, config)
  end

  defp add_scheme_opts(opts, %URI{scheme: "http"}), do: opts

  defp add_scheme_opts(opts, %URI{scheme: "https", host: host}) do
    ssl_opts = [
      ssl_options: [
        # Workaround for remote server certificate chain issues
        partial_chain: &:hackney_connect.partial_chain/1,

        # We don't support TLS v1.3 yet
        versions: [:tlsv1, :"tlsv1.1", :"tlsv1.2"],
        server_name_indication: to_charlist(host)
      ]
    ]

    Keyword.merge(opts, ssl_opts)
  end

  defp maybe_add_proxy(opts), do: Pleroma.HTTP.Proxy.maybe_add_proxy(opts)

  defp merge_with_incoming_opts(opts, incoming), do: Keyword.merge(opts, incoming)

  defp add_pool_timeout(opts) do
    timeout = Pleroma.Config.get([:hackney_pools, opts[:pool], :timeout], 10_000)
    Keyword.put(opts, :timeout, timeout)
  end
end
