# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Gun.Connections do
  use GenServer

  @type domain :: String.t()
  @type conn :: Gun.Conn.t()
  @type t :: %__MODULE__{
          conns: %{domain() => conn()}
        }

  defstruct conns: %{}

  def start_link(name \\ __MODULE__)

  def start_link(name) when is_atom(name) do
    GenServer.start_link(__MODULE__, [], name: name)
  end

  def start_link(_) do
    if Application.get_env(:tesla, :adapter) == Tesla.Adapter.Gun do
      GenServer.start_link(__MODULE__, [])
    else
      :ignore
    end
  end

  @impl true
  def init(_) do
    {:ok, %__MODULE__{conns: %{}}}
  end

  @spec get_conn(String.t(), keyword(), atom()) :: pid()
  def get_conn(url, opts \\ [], name \\ __MODULE__) do
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

  # TODO: only for testing, add this parameter to the config
  @spec try_to_get_gun_conn(String.t(), keyword(), atom()) :: nil | pid()
  def try_to_get_gun_conn(url, opts \\ [], name \\ __MODULE__),
    do: try_to_get_gun_conn(url, opts, name, 0)

  @spec try_to_get_gun_conn(String.t(), keyword(), atom(), pos_integer()) :: nil | pid()
  def try_to_get_gun_conn(_url, _, _, 3), do: nil

  def try_to_get_gun_conn(url, opts, name, acc) do
    case Pleroma.Gun.Connections.get_conn(url, opts, name) do
      nil -> try_to_get_gun_conn(url, acc + 1)
      conn -> conn
    end
  end

  @spec alive?(atom()) :: boolean()
  def alive?(name \\ __MODULE__) do
    pid = Process.whereis(name)
    if pid, do: Process.alive?(pid), else: false
  end

  @spec get_state(atom()) :: t()
  def get_state(name \\ __MODULE__) do
    GenServer.call(name, {:state})
  end

  @impl true
  def handle_call({:conn, %{opts: opts, uri: uri}}, from, state) do
    key = compose_key(uri)

    case state.conns[key] do
      %{conn: conn, state: conn_state} when conn_state == :up ->
        {:reply, conn, state}

      %{state: conn_state, waiting_pids: pids} when conn_state in [:open, :down] ->
        state = put_in(state.conns[key].waiting_pids, [from | pids])
        {:noreply, state}

      nil ->
        {:ok, conn} = Pleroma.Gun.API.open(to_charlist(uri.host), uri.port, opts)

        state =
          put_in(state.conns[key], %Pleroma.Gun.Conn{
            conn: conn,
            waiting_pids: [from],
            protocol: String.to_atom(uri.scheme)
          })

        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:state}, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info({:gun_up, conn_pid, _protocol}, state) do
    {key, conn} = find_conn(state.conns, conn_pid)

    # Send to all waiting processes connection pid
    Enum.each(conn.waiting_pids, fn waiting_pid -> GenServer.reply(waiting_pid, conn_pid) end)

    # Update state of the current connection and set waiting_pids to empty list
    state = put_in(state.conns[key], %{conn | state: :up, waiting_pids: []})
    {:noreply, state}
  end

  @impl true
  # Do we need to do something with killed & unprocessed references?
  def handle_info({:gun_down, conn_pid, _protocol, _reason, _killed, _unprocessed}, state) do
    {key, conn} = find_conn(state.conns, conn_pid)

    # We don't want to block requests to GenServer.
    # If gun sends a down message, return nil, so we can make some
    # retries, while the connection is not up.
    Enum.each(conn.waiting_pids, fn waiting_pid -> GenServer.reply(waiting_pid, nil) end)

    state = put_in(state.conns[key].state, :down)
    {:noreply, state}
  end

  defp compose_key(uri), do: uri.host <> ":" <> to_string(uri.port)

  defp find_conn(conns, conn_pid) do
    Enum.find(conns, fn {key, conn} ->
      protocol = if String.ends_with?(key, ":443"), do: :https, else: :http
      conn.conn == conn_pid and conn.protocol == protocol
    end)
  end
end
