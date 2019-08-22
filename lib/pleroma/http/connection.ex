# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP.Connection do
  @moduledoc """
  Connection for http-requests.
  """

  @options [
    connect_timeout: 10_000,
    timeout: 20_000,
    pool: :federation,
    version: :master
  ]

  @doc """
  Configure a client connection

  # Returns

  Tesla.Env.client
  """
  @spec new(Keyword.t()) :: Tesla.Env.client()
  def new(opts \\ []) do
    middleware = [Tesla.Middleware.FollowRedirects]
    adapter = Application.get_env(:tesla, :adapter)
    Tesla.client(middleware, {adapter, options(opts)})
  end

  # fetch http options
  #
  def options(opts) do
    options = Keyword.get(opts, :adapter, [])
    adapter_options = Pleroma.Config.get([:http, :adapter], [])
    proxy_url = Pleroma.Config.get([:http, :proxy_url], nil)

    options =
      @options
      |> Keyword.merge(adapter_options)
      |> Keyword.merge(options)
      |> Keyword.merge(proxy: proxy_url)

    pool = options[:pool]
    url = options[:url]

    if not is_nil(url) and not is_nil(pool) and Pleroma.Gun.Connections.alive?(pool) do
      get_conn_for_gun(url, options, pool)
    else
      options
    end
  end

  defp get_conn_for_gun(url, options, pool) do
    case Pleroma.Gun.Connections.get_conn(url, options, pool) do
      nil ->
        options

      conn ->
        %{host: host, port: port} = URI.parse(url)

        # verify sertificates opts for gun
        tls_opts = [
          verify: :verify_peer,
          cacerts: :certifi.cacerts(),
          depth: 20,
          server_name_indication: to_charlist(host),
          reuse_sessions: false,
          verify_fun: {&:ssl_verify_hostname.verify_fun/3, [check_hostname: to_charlist(host)]}
        ]

        Keyword.put(options, :conn, conn)
        |> Keyword.put(:close_conn, false)
        |> Keyword.put(:original, "#{host}:#{port}")
        |> Keyword.put(:tls_opts, tls_opts)
    end
  end
end
