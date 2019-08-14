# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Gun.API.Mock do
  @behaviour Pleroma.Gun.API
  @impl Pleroma.Gun.API
  def open('some-domain.com', 80, %{genserver_pid: genserver_pid}) do
    {:ok, conn_pid} = Task.start_link(fn -> Process.sleep(1_000) end)
    send(genserver_pid, {:gun_up, conn_pid, :http})
    {:ok, conn_pid}
  end

  def open('some-domain.com', 443, %{genserver_pid: genserver_pid}) do
    {:ok, conn_pid} = Task.start_link(fn -> Process.sleep(1_000) end)
    send(genserver_pid, {:gun_up, conn_pid, :http2})
    {:ok, conn_pid}
  end

  @impl Pleroma.Gun.API
  def open('gun_down.com', _port, %{genserver_pid: genserver_pid}) do
    {:ok, conn_pid} = Task.start_link(fn -> Process.sleep(1_000) end)
    send(genserver_pid, {:gun_down, conn_pid, :http, nil, nil, nil})
    {:ok, conn_pid}
  end

  @impl Pleroma.Gun.API
  def open('gun_down_and_up.com', _port, %{genserver_pid: genserver_pid}) do
    {:ok, conn_pid} = Task.start_link(fn -> Process.sleep(1_000) end)
    send(genserver_pid, {:gun_down, conn_pid, :http, nil, nil, nil})

    {:ok, _} =
      Task.start_link(fn ->
        Process.sleep(500)
        send(genserver_pid, {:gun_up, conn_pid, :http})
      end)

    {:ok, conn_pid}
  end
end
