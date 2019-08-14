# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP.Connection do
  @moduledoc """
  Connection for http-requests.
  """

  @options [
    connect_timeout: 10_000,
    timeout: 20_000
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
    options = options(opts)
    Tesla.client(middleware, {adapter, options})
  end

  # fetch http options
  #
  def options(opts) do
    options = Keyword.get(opts, :adapter, [])
    adapter_options = Pleroma.Config.get([:http, :adapter], [])
    proxy_url = Pleroma.Config.get([:http, :proxy_url], nil)

    @options
    |> Keyword.merge(adapter_options)
    |> Keyword.merge(options)
    |> Keyword.merge(proxy: proxy_url)
  end
end
