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
    pool: :federation
  ]

  require Logger

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

    proxy =
      case parse_proxy(proxy_url) do
        {:ok, proxy_host, proxy_port} -> {proxy_host, proxy_port}
        _ -> nil
      end

    options =
      @options
      |> Keyword.merge(adapter_options)
      |> Keyword.merge(options)
      |> Keyword.merge(proxy: proxy)

    pool = options[:pool]
    url = options[:url]

    if not is_nil(url) and not is_nil(pool) and Pleroma.Gun.Connections.alive?(pool) do
      get_conn_for_gun(url, options, pool)
    else
      options
    end
  end

  defp get_conn_for_gun(url, options, pool) do
    case Pleroma.Gun.Connections.checkin(url, options, pool) do
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

  @spec parse_proxy(String.t() | tuple() | nil) ::
          {tuple, pos_integer()} | {:error, atom()} | nil
  def parse_proxy(nil), do: nil

  def parse_proxy(proxy) when is_binary(proxy) do
    with [host, port] <- String.split(proxy, ":"),
         {port, ""} <- Integer.parse(port) do
      {:ok, parse_host(host), port}
    else
      {_, _} ->
        Logger.warn("parsing port in proxy fail #{inspect(proxy)}")
        {:error, :error_parsing_port_in_proxy}

      :error ->
        Logger.warn("parsing port in proxy fail #{inspect(proxy)}")
        {:error, :error_parsing_port_in_proxy}

      _ ->
        Logger.warn("parsing proxy fail #{inspect(proxy)}")
        {:error, :error_parsing_proxy}
    end
  end

  def parse_proxy(proxy) when is_tuple(proxy) do
    with {_type, host, port} <- proxy do
      {:ok, parse_host(host), port}
    else
      _ ->
        Logger.warn("parsing proxy fail #{inspect(proxy)}")
        {:error, :error_parsing_proxy}
    end
  end

  @spec parse_host(String.t() | tuple()) :: charlist() | atom()
  def parse_host(host) when is_atom(host), do: to_charlist(host)

  def parse_host(host) when is_binary(host) do
    host = to_charlist(host)

    case :inet.parse_address(host) do
      {:error, :einval} -> host
      {:ok, ip} -> ip
    end
  end
end
