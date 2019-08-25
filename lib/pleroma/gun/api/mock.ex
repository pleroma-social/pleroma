# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Gun.API.Mock do
  @behaviour Pleroma.Gun.API

  alias Pleroma.Gun.API

  @impl API
  def open(domain, 80, %{genserver_pid: genserver_pid})
      when domain in ['another-domain.com', 'some-domain.com'] do
    {:ok, conn_pid} = Task.start_link(fn -> Process.sleep(1_000) end)

    Registry.register(API.Mock, conn_pid, %{
      origin_scheme: "http",
      origin_host: domain,
      origin_port: 80
    })

    send(genserver_pid, {:gun_up, conn_pid, :http})
    {:ok, conn_pid}
  end

  @impl API
  def open('some-domain.com', 443, %{genserver_pid: genserver_pid}) do
    {:ok, conn_pid} = Task.start_link(fn -> Process.sleep(1_000) end)

    Registry.register(API.Mock, conn_pid, %{
      origin_scheme: "https",
      origin_host: 'some-domain.com',
      origin_port: 443
    })

    send(genserver_pid, {:gun_up, conn_pid, :http2})
    {:ok, conn_pid}
  end

  @impl API
  def open('gun_down.com', 80, %{genserver_pid: genserver_pid}) do
    {:ok, conn_pid} = Task.start_link(fn -> Process.sleep(1_000) end)

    Registry.register(API.Mock, conn_pid, %{
      origin_scheme: "http",
      origin_host: 'gun_down.com',
      origin_port: 80
    })

    send(genserver_pid, {:gun_down, conn_pid, :http, nil, nil, nil})
    {:ok, conn_pid}
  end

  @impl API
  def open('gun_down_and_up.com', 80, %{genserver_pid: genserver_pid}) do
    {:ok, conn_pid} = Task.start_link(fn -> Process.sleep(1_000) end)

    Registry.register(API.Mock, conn_pid, %{
      origin_scheme: "http",
      origin_host: 'gun_down_and_up.com',
      origin_port: 80
    })

    send(genserver_pid, {:gun_down, conn_pid, :http, nil, nil, nil})

    {:ok, _} =
      Task.start_link(fn ->
        Process.sleep(500)

        send(genserver_pid, {:gun_up, conn_pid, :http})
      end)

    {:ok, conn_pid}
  end

  @impl API
  def open({127, 0, 0, 1}, 8123, _) do
    Task.start_link(fn -> Process.sleep(1_000) end)
  end

  @impl API
  def open('localhost', 9050, _) do
    Task.start_link(fn -> Process.sleep(1_000) end)
  end

  @impl API
  def await_up(_pid) do
    {:ok, :http}
  end

  @impl API
  def connect(pid, %{host: _, port: 80}) do
    ref = make_ref()
    Registry.register(API.Mock, ref, pid)
    ref
  end

  @impl API
  def connect(pid, %{host: _, port: 443, protocols: [:http2], transport: :tls}) do
    ref = make_ref()
    Registry.register(API.Mock, ref, pid)
    ref
  end

  @impl API
  def await(pid, ref) do
    [{_, ^pid}] = Registry.lookup(API.Mock, ref)
    {:response, :fin, 200, []}
  end

  @impl API
  def info(pid) do
    [{_, info}] = Registry.lookup(API.Mock, pid)
    info
  end

  @impl API
  def close(_pid), do: :ok
end
