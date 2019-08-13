# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Gun.API do
  @callback open(charlist(), pos_integer(), map()) :: {:ok, pid()}

  def open(host, port, opts) do
    api().open(host, port, opts)
  end

  defp api do
    Pleroma.Config.get([Pleroma.Gun.API], :gun)
  end
end
