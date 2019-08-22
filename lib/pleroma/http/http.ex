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
      options = process_request_options(options)

      adapter_gun? = Application.get_env(:tesla, :adapter) == Tesla.Adapter.Gun

      options =
        if adapter_gun? do
          adapter_opts =
            Keyword.get(options, :adapter, [])
            |> Keyword.put(:url, url)

          Keyword.put(options, :adapter, adapter_opts)
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
