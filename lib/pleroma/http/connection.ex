# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP.Connection do
  @moduledoc """
  Configure Tesla.Client with default and customized adapter options.
  """

  require Logger

  @type ipv4_address :: {0..255, 0..255, 0..255, 0..255}
  @type ipv6_address ::
          {0..65_535, 0..65_535, 0..65_535, 0..65_535, 0..65_535, 0..65_535, 0..65_535, 0..65_535}
  @type host() :: charlist() | ipv4_address() | ipv6_address()

  @doc """
  Merge default connection & adapter options with received options.
  """

  @spec options(URI.t(), keyword()) :: keyword()
  def options(%URI{} = uri, opts \\ []) do
    adapter = Application.get_env(:tesla, :adapter)

    [pool: :federation]
    |> Keyword.merge(opts)
    |> adapter_options(uri, adapter)
  end

  @spec format_host(String.t() | atom() | charlist()) :: host()
  def format_host(host) when is_list(host), do: host
  def format_host(host) when is_atom(host), do: to_charlist(host)

  def format_host(host) when is_binary(host) do
    host = to_charlist(host)

    case :inet.parse_address(host) do
      {:error, :einval} -> host
      {:ok, ip} -> ip
    end
  end

  defp adapter_options(opts, uri, Tesla.Adapter.Gun), do: Pleroma.HTTP.Gun.options(opts, uri)

  defp adapter_options(opts, uri, Tesla.Adapter.Hackney),
    do: Pleroma.HTTP.Hackney.options(opts, uri)

  defp adapter_options(opts, _, _), do: Keyword.put(opts, :env, Pleroma.Config.get(:env))
end
