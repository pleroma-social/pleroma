# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Gun.Connections do
  use GenServer

  @type domain :: String.t()
  @type conn :: Pleroma.Gun.Conn.t()

  @type t :: %__MODULE__{
          conns: %{domain() => conn()},
          opts: keyword()
        }

  defstruct conns: %{}, opts: []

  alias Pleroma.Gun.API

  @spec start_link({atom(), keyword()}) :: {:ok, pid()} | :ignore
  def start_link({name, opts}) do
    if Application.get_env(:tesla, :adapter) == Tesla.Adapter.Gun do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      :ignore
    end
  end

  @impl true
  def init(opts), do: {:ok, %__MODULE__{conns: %{}, opts: opts}}

  @spec get_conn(String.t(), keyword(), atom()) :: pid()
  def get_conn(url, opts \\ [], name \\ :default) do
    opts = Enum.into(opts, %{})

    uri = URI.parse(url)

    opts =
      if uri.scheme == "https" and uri.port != 443,
        do: Map.put(opts, :transport, :tls),
        else: opts

    GenServer.call(
      name,
      {:conn, %{opts: opts, uri: uri}}
    )
  end

  @spec alive?(atom()) :: boolean()
  def alive?(name \\ :default) do
    pid = Process.whereis(name)
    if pid, do: Process.alive?(pid), else: false
  end

  @spec get_state(atom()) :: t()
  def get_state(name \\ :default) do
    GenServer.call(name, {:state})
  end

  @impl true
  def handle_call({:conn, %{opts: opts, uri: uri}}, from, state) do
    key = compose_key(uri)

    case state.conns[key] do
      %{conn: conn, state: conn_state, used: used} when conn_state == :up ->
        state = put_in(state.conns[key].used, used + 1)
        {:reply, conn, state}

      %{state: conn_state, waiting_pids: pids} when conn_state in [:open, :down] ->
        state = put_in(state.conns[key].waiting_pids, [from | pids])
        {:noreply, state}

      nil ->
        max_connections = state.opts[:max_connections]

        if Enum.count(state.conns) < max_connections do
          open_conn(key, uri, from, state, opts)
        else
          [{close_key, least_used} | _conns] = Enum.sort_by(state.conns, fn {_k, v} -> v.used end)

          :ok = API.close(least_used.conn)

          state =
            put_in(
              state.conns,
              Map.delete(state.conns, close_key)
            )

          open_conn(key, uri, from, state, opts)
        end
    end
  end

  @impl true
  def handle_call({:state}, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info({:gun_up, conn_pid, _protocol}, state) do
    conn_key = compose_key_gun_info(conn_pid)
    {key, conn} = find_conn(state.conns, conn_pid, conn_key)

    # Send to all waiting processes connection pid
    Enum.each(conn.waiting_pids, fn waiting_pid -> GenServer.reply(waiting_pid, conn_pid) end)

    # Update state of the current connection and set waiting_pids to empty list
    state =
      put_in(state.conns[key], %{
        conn
        | state: :up,
          waiting_pids: [],
          used: conn.used + length(conn.waiting_pids)
      })

    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_down, conn_pid, _protocol, _reason, _killed, _unprocessed}, state) do
    conn_key = compose_key_gun_info(conn_pid)
    {key, conn} = find_conn(state.conns, conn_pid, conn_key)

    Enum.each(conn.waiting_pids, fn waiting_pid -> GenServer.reply(waiting_pid, nil) end)

    state = put_in(state.conns[key].state, :down)
    {:noreply, state}
  end

  defp compose_key(uri), do: "#{uri.scheme}:#{uri.host}:#{uri.port}"

  defp compose_key_gun_info(pid) do
    info = API.info(pid)
    "#{info.origin_scheme}:#{info.origin_host}:#{info.origin_port}"
  end

  defp find_conn(conns, conn_pid, conn_key) do
    Enum.find(conns, fn {key, conn} ->
      key == conn_key and conn.conn == conn_pid
    end)
  end

  defp open_conn(key, uri, from, state, opts) do
    {:ok, conn} = API.open(to_charlist(uri.host), uri.port, opts)

    state =
      put_in(state.conns[key], %Pleroma.Gun.Conn{
        conn: conn,
        waiting_pids: [from]
      })

    {:noreply, state}
  end
end
