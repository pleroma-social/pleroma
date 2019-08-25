# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Gun.API.Gun do
  @behaviour Pleroma.Gun.API

  alias Pleroma.Gun.API

  @gun_keys [
    :connect_timeout,
    :http_opts,
    :http2_opts,
    :protocols,
    :retry,
    :retry_timeout,
    :trace,
    :transport,
    :tls_opts,
    :tcp_opts,
    :ws_opts
  ]

  @impl API
  def open(host, port, opts) do
    :gun.open(host, port, Map.take(opts, @gun_keys))
  end

  @impl API
  def info(pid), do: :gun.info(pid)

  @impl API
  def close(pid), do: :gun.close(pid)

  @impl API
  def await_up(pid), do: :gun.await_up(pid)

  @impl API
  def connect(pid, opts), do: :gun.connect(pid, opts)

  @impl API
  def await(pid, ref), do: :gun.await(pid, ref)
end
