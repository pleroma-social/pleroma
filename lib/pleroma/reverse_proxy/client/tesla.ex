# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-onl

defmodule Pleroma.ReverseProxy.Client.Tesla do
  @behaviour Pleroma.ReverseProxy.Client

  @adapters [Tesla.Adapter.Gun]

  def request(method, url, headers, body, opts \\ []) do
    adapter_opts =
      Keyword.get(opts, :adapter, [])
      |> Keyword.put(:body_as, :chunks)

    with {:ok, response} <-
           Pleroma.HTTP.request(
             method,
             url,
             body,
             headers,
             Keyword.put(opts, :adapter, adapter_opts)
           ) do
      if is_map(response.body),
        do: {:ok, response.status, response.headers, response.body},
        else: {:ok, response.status, response.headers}
    else
      {:error, error} -> {:error, error}
    end
  end

  def stream_body(%{fin: true}), do: :done

  def stream_body(client) do
    case read_chunk!(client) do
      {:fin, body} -> {:ok, body, Map.put(client, :fin, true)}
      {:nofin, part} -> {:ok, part, client}
      {:error, error} -> {:error, error}
    end
  end

  defp read_chunk!(%{pid: pid, stream: stream, opts: opts}) do
    adapter = Application.get_env(:tesla, :adapter)

    unless adapter in @adapters do
      raise "#{adapter} doesn't support reading body in chunks"
    end

    adapter.read_chunk(pid, stream, opts)
  end

  def close(pid) do
    adapter = Application.get_env(:tesla, :adapter)

    unless adapter in @adapters do
      raise "#{adapter} doesn't support closing connection"
    end

    adapter.close(pid)
  end
end
