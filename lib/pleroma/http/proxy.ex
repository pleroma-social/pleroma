# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP.Proxy do
  require Logger

  alias Pleroma.HTTP.Connection

  @type proxy_type() :: :socks4 | :socks5

  @spec parse_proxy(String.t() | tuple() | nil) ::
          {:ok, Connection.host(), pos_integer()}
          | {:ok, proxy_type(), Connection.host(), pos_integer()}
          | {:error, atom()}
          | nil

  def parse_proxy(nil), do: nil

  def parse_proxy(proxy) when is_binary(proxy) do
    with [host, port] <- String.split(proxy, ":"),
         {port, ""} <- Integer.parse(port) do
      {:ok, Connection.format_host(host), port}
    else
      {_, _} ->
        Logger.warn("Parsing port failed #{inspect(proxy)}")
        {:error, :invalid_proxy_port}

      :error ->
        Logger.warn("Parsing port failed #{inspect(proxy)}")
        {:error, :invalid_proxy_port}

      _ ->
        Logger.warn("Parsing proxy failed #{inspect(proxy)}")
        {:error, :invalid_proxy}
    end
  end

  def parse_proxy(proxy) when is_tuple(proxy) do
    with {type, host, port} <- proxy do
      {:ok, type, Connection.format_host(host), port}
    else
      _ ->
        Logger.warn("Parsing proxy failed #{inspect(proxy)}")
        {:error, :invalid_proxy}
    end
  end

  defp format_proxy(nil), do: nil

  defp format_proxy(proxy_url) do
    case parse_proxy(proxy_url) do
      {:ok, host, port} -> {host, port}
      {:ok, type, host, port} -> {type, host, port}
      _ -> nil
    end
  end

  @spec maybe_add_proxy(keyword()) :: keyword()
  def maybe_add_proxy(opts) do
    proxy =
      Pleroma.Config.get([:http, :proxy_url])
      |> format_proxy()

    if proxy do
      Keyword.put_new(opts, :proxy, proxy)
    else
      opts
    end
  end
end
