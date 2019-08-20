# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP do
  @moduledoc """

  """

  alias Pleroma.HTTP.Connection
  alias Pleroma.HTTP.RequestBuilder, as: Builder

  @type t :: __MODULE__

  @doc """
  Builds and perform http request.

  # Arguments:
  `method` - :get, :post, :put, :delete
  `url`
  `body`
  `headers` - a keyworld list of headers, e.g. `[{"content-type", "text/plain"}]`
  `options` - custom, per-request middleware or adapter options

  # Returns:
  `{:ok, %Tesla.Env{}}` or `{:error, error}`

  """
  def request(method, url, body \\ "", headers \\ [], options \\ []) do
    try do
      options =
        process_request_options(options)
        |> process_sni_options(url)

      adapter_gun? = Application.get_env(:tesla, :adapter) == Tesla.Adapter.Gun

      pool = options[:adapter][:pool]

      options =
        if adapter_gun? and not is_nil(pool) and Pleroma.Gun.Connections.alive?(pool) do
          get_conn_for_gun(url, options, pool)
        else
          options
        end

      params = Keyword.get(options, :params, [])

      %{}
      |> Builder.method(method)
      |> Builder.url(url)
      |> Builder.headers(headers)
      |> Builder.opts(options)
      |> Builder.add_param(:body, :body, body)
      |> Builder.add_param(:query, :query, params)
      |> Enum.into([])
      |> (&Tesla.request(Connection.new(options), &1)).()
    rescue
      e ->
        {:error, e}
    catch
      :exit, e ->
        {:error, e}
    end
  end

  defp get_conn_for_gun(url, options, pool) do
    case Pleroma.Gun.Connections.get_conn(url, options, pool) do
      nil ->
        options

      conn ->
        %{host: host, port: port} = URI.parse(url)

        adapter_opts =
          Keyword.get(options, :adapter, [])
          |> Keyword.put(:conn, conn)
          |> Keyword.put(:close_conn, false)
          |> Keyword.put(:original, "#{host}:#{port}")

        Keyword.put(options, :adapter, adapter_opts)
    end
  end

  defp process_sni_options(options, nil), do: options

  defp process_sni_options(options, url) do
    uri = URI.parse(url)
    host = uri.host |> to_charlist()

    case uri.scheme do
      "https" ->
        options ++ [ssl: [server_name_indication: host]]

      _ ->
        options
    end
  end

  def process_request_options(options) do
    Keyword.merge(Pleroma.HTTP.Connection.options([]), options)
  end

  @doc """
  Performs GET request.

  See `Pleroma.HTTP.request/5`
  """
  def get(url, headers \\ [], options \\ []),
    do: request(:get, url, "", headers, options)

  @doc """
  Performs POST request.

  See `Pleroma.HTTP.request/5`
  """
  def post(url, body, headers \\ [], options \\ []),
    do: request(:post, url, body, headers, options)
end
