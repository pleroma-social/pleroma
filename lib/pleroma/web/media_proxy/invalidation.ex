# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MediaProxy.Invalidation do
  @moduledoc false

  @callback purge(list(String.t()), Keyword.t()) :: {:ok, String.t()} | {:error, String.t()}

  alias Pleroma.Config
  alias Pleroma.Web.MediaProxy

  @spec purge(list(String.t())) :: {:ok, String.t()} | {:error, String.t()}
  def purge(urls) do
    [:media_proxy, :invalidation, :enabled]
    |> Config.get()
    |> do_purge(urls)
  end

  defp do_purge(true, urls) do
    provider = Config.get([:media_proxy, :invalidation, :provider])
    options = Config.get(provider)

    urls
    |> List.wrap()
    |> Enum.map(&MediaProxy.url(&1))
    |> provider.purge(options)
  end

  defp do_purge(_, _), do: :ok
end
