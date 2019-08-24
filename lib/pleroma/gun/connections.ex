# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Gun.Connections do
  use GenServer
  require Logger

  @type domain :: String.t()
  @type conn :: Pleroma.Gun.Conn.t()

  @type t :: %__MODULE__{
          conns: %{domain() => conn()},
          opts: keyword()
        }

  defstruct conns: %{}, opts: []

  alias Pleroma.Gun.API
  alias Pleroma.Gun.Conn

  @spec start_link({atom(), keyword()}) :: {:ok, pid()} | :ignore
  def start_link({name, opts}) do
    GenServer.start_link(__MODULE__, opts, name: name)
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

    opts =
      if uri.scheme == "https" do
        host = uri.host |> to_charlist()

        tls_opts =
          Map.get(opts, :tls_opts, [])
          |> Keyword.put(:server_name_indication, host)

        Map.put(opts, :tls_opts, tls_opts)
      else
        opts
      end

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
      %{conn: conn, state: conn_state, last_reference: reference, crf: last_crf} = current_conn
      when conn_state == :up ->
        time = current_time()
        last_reference = time - reference

        current_crf = crf(last_reference, 100, last_crf)

        state =
          put_in(state.conns[key], %{
            current_conn
            | last_reference: time,
              crf: current_crf
          })

        {:reply, conn, state}

      %{state: conn_state, waiting_pids: pids} when conn_state in [:open, :down] ->
        state = put_in(state.conns[key].waiting_pids, [from | pids])
        {:noreply, state}

      nil ->
        max_connections = state.opts[:max_connections]

        if Enum.count(state.conns) < max_connections do
          open_conn(key, uri, from, state, opts)
        else
          [{close_key, least_used} | _conns] =
            state.conns
            |> Enum.filter(fn {_k, v} -> v.waiting_pids == [] end)
            |> Enum.sort(fn {_x_k, x}, {_y_k, y} ->
              x.crf < y.crf and x.last_reference < y.last_reference
            end)

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
    time = current_time()
    last_reference = time - conn.last_reference
    current_crf = crf(last_reference, 100, conn.crf)

    state =
      put_in(state.conns[key], %{
        conn
        | state: :up,
          waiting_pids: [],
          last_reference: time,
          crf: current_crf
      })

    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_down, conn_pid, _protocol, _reason, _killed, _unprocessed}, state) do
    # we can't get info on this pid, because pid is dead
    {key, conn} = find_conn(state.conns, conn_pid)

    Enum.each(conn.waiting_pids, fn waiting_pid -> GenServer.reply(waiting_pid, nil) end)

    state = put_in(state.conns[key].state, :down)
    {:noreply, state}
  end

  defp compose_key(uri), do: "#{uri.scheme}:#{uri.host}:#{uri.port}"

  defp compose_key_gun_info(pid) do
    info = API.info(pid)
    "#{info.origin_scheme}:#{info.origin_host}:#{info.origin_port}"
  end

  defp find_conn(conns, conn_pid) do
    Enum.find(conns, fn {_key, conn} ->
      conn.conn == conn_pid
    end)
  end

  defp find_conn(conns, conn_pid, conn_key) do
    Enum.find(conns, fn {key, conn} ->
      key == conn_key and conn.conn == conn_pid
    end)
  end

  defp open_conn(key, uri, _from, state, %{proxy: {proxy_host, proxy_port}} = opts) do
    host = to_charlist(uri.host)
    port = uri.port

    tls_opts = Map.get(opts, :tls_opts, [])
    connect_opts = %{host: host, port: port}

    connect_opts =
      if uri.scheme == "https" do
        Map.put(connect_opts, :protocols, [:http2])
        |> Map.put(:transport, :tls)
        |> Map.put(:tls_opts, tls_opts)
      else
        connect_opts
      end

    with open_opts <- Map.delete(opts, :tls_opts),
         {:ok, conn} <- API.open(proxy_host, proxy_port, open_opts),
         {:ok, _} <- API.await_up(conn),
         stream <- API.connect(conn, connect_opts),
         {:response, :fin, 200, _} <- API.await(conn, stream) do
      state =
        put_in(state.conns[key], %Conn{
          conn: conn,
          waiting_pids: [],
          state: :up
        })

      {:reply, conn, state}
    else
      error ->
        Logger.warn(inspect(error))
        {:reply, nil, state}
    end
  end

  defp open_conn(key, uri, from, state, opts) do
    host = to_charlist(uri.host)
    port = uri.port

    with {:ok, conn} <- API.open(host, port, opts) do
      state =
        put_in(state.conns[key], %Conn{
          conn: conn,
          waiting_pids: [from]
        })

      {:noreply, state}
    else
      error ->
        Logger.warn(inspect(error))
        {:reply, nil, state}
    end
  end

  defp current_time do
    :os.system_time(:second)
  end

  def crf(current, steps, crf) do
    1 + :math.pow(0.5, current / steps) * crf
  end
end
