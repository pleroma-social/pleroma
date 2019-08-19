# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Gun.API do
  @callback open(charlist(), pos_integer(), map()) :: {:ok, pid()}
  @callback info(pid()) :: map()
  @callback close(pid()) :: :ok

  def open(host, port, opts) do
    api().open(host, port, opts)
  end

  def info(pid) do
    api().info(pid)
  end

  def close(pid) do
    api().close(pid)
  end

  defp api do
    Pleroma.Config.get([Pleroma.Gun.API], Pleroma.Gun.API.Gun)
  end
end
