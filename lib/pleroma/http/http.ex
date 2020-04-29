# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP do
  @moduledoc """
    Wrapper for `Tesla.request/2`.
  """

  alias Pleroma.HTTP.Request
  alias Pleroma.HTTP.Request.Builder
  alias Tesla.Client
  alias Tesla.Env

  require Logger

  @type t :: __MODULE__

  @doc """
  Performs GET request.

  See `Pleroma.HTTP.request/5`
  """
  @spec get(Request.url() | nil, Request.headers(), keyword()) ::
          nil | {:ok, Env.t()} | {:error, any()}
  def get(url, headers \\ [], options \\ [])
  def get(nil, _, _), do: nil
  def get(url, headers, options), do: request(:get, url, "", headers, options)

  @doc """
  Performs POST request.

  See `Pleroma.HTTP.request/5`
  """
  @spec post(Request.url(), String.t(), Request.headers(), keyword()) ::
          {:ok, Env.t()} | {:error, any()}
  def post(url, body, headers \\ [], options \\ []),
    do: request(:post, url, body, headers, options)

  @doc """
  Builds and performs http request.

  # Arguments:
  `method` - :get, :post, :put, :delete
  `url` - full url
  `body` - request body
  `headers` - a keyworld list of headers, e.g. `[{"content-type", "text/plain"}]`
  `options` - custom, per-request middleware or adapter options

  # Returns:
  `{:ok, %Tesla.Env{}}` or `{:error, error}`

  """
  @spec request(atom(), Request.url(), String.t(), Request.headers(), keyword()) ::
          {:ok, Env.t()} | {:error, any()}
  def request(method, url, body, headers, options) when is_binary(url) do
    uri = URI.parse(url)
    adapter_opts = Pleroma.HTTP.Connection.options(uri, options[:adapter] || [])
    options = put_in(options[:adapter], adapter_opts)

    adapter = Application.get_env(:tesla, :adapter)

    client = Tesla.client([Pleroma.HTTP.Middleware.FollowRedirects], adapter)
    request = build_request(method, headers, options, url, body)

    request(client, request, Enum.into(adapter_opts, %{}))
  end

  @spec request(Client.t(), keyword(), map()) :: {:ok, Env.t()} | {:error, any()}
  def request(client, request, %{env: :test}), do: request(client, request)

  def request(client, request, %{body_as: :chunks}), do: request(client, request)

  def request(client, request, %{pool_alive?: false}), do: request(client, request)

  def request(client, request, %{pool: pool, timeout: timeout}) do
    :poolboy.transaction(
      pool,
      &Pleroma.Pool.Request.execute(&1, client, request, timeout),
      timeout
    )
  end

  @spec request(Client.t(), keyword()) :: {:ok, Env.t()} | {:error, any()}
  def request(client, request), do: Tesla.request(client, request)

  defp build_request(method, headers, options, url, body) do
    Builder.new()
    |> Builder.method(method)
    |> Builder.headers(headers)
    |> Builder.opts(options)
    |> Builder.url(url)
    |> Builder.add_param(:body, :body, body)
    |> Builder.convert_to_keyword()
  end
end
