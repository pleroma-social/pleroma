# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Pool.Connections do
  use GenServer

  alias Pleroma.Config
  alias Pleroma.Gun
  alias Pleroma.Gun.Conn

  require Logger

  @type domain :: String.t()
  @type conn :: Conn.t()
  @type seconds :: pos_integer()

  @type t :: %__MODULE__{
          conns: %{domain() => conn()},
          opts: keyword()
        }

  defstruct conns: %{}, opts: []

  @spec start_link({atom(), keyword()}) :: {:ok, pid()}
  def start_link({name, opts}) do
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    schedule_close_idle_conns()
    {:ok, %__MODULE__{conns: %{}, opts: opts}}
  end

  @spec checkin(String.t() | URI.t(), atom()) :: pid() | nil
  def checkin(url, name, opts \\ [])
  def checkin(url, name, opts) when is_binary(url), do: checkin(URI.parse(url), name, opts)

  def checkin(%URI{} = uri, name, opts) do
    GenServer.call(name, {:checkin, uri, opts, name})
  end

  @spec alive?(atom()) :: boolean()
  def alive?(name) do
    if pid = Process.whereis(name) do
      Process.alive?(pid)
    else
      false
    end
  end

  @spec get_state(atom()) :: t()
  def get_state(name) do
    GenServer.call(name, :state)
  end

  @spec count(atom()) :: pos_integer()
  def count(name) do
    GenServer.call(name, :count)
  end

  @spec get_unused_conns(atom()) :: [{domain(), conn()}]
  def get_unused_conns(name) do
    GenServer.call(name, :unused_conns)
  end

  @spec checkout(pid(), pid(), atom()) :: :ok
  def checkout(conn, pid, name) do
    GenServer.cast(name, {:checkout, conn, pid})
  end

  @spec add_conn(atom(), String.t(), Conn.t()) :: :ok
  def add_conn(name, key, conn) do
    GenServer.cast(name, {:add_conn, key, conn})
  end

  @spec update_conn(atom(), String.t(), pid()) :: :ok
  def update_conn(name, key, conn_pid) do
    GenServer.cast(name, {:update_conn, key, conn_pid})
  end

  @spec remove_conn(atom(), String.t()) :: :ok
  def remove_conn(name, key) do
    GenServer.cast(name, {:remove_conn, key})
  end

  @spec refresh(atom()) :: :ok
  def refresh(name) do
    GenServer.call(name, :refresh)
  end

  @impl true
  def handle_cast({:add_conn, key, conn}, state) do
    {:noreply, put_in(state.conns[key], conn)}
  end

  @impl true
  def handle_cast({:update_conn, key, conn_pid}, state) do
    conn = state.conns[key]

    Process.monitor(conn_pid)

    conn =
      Enum.reduce(conn.awaited_by, conn, fn waiting, conn ->
        GenServer.reply(waiting, conn_pid)
        time = :os.system_time(:second)
        last_reference = time - conn.last_reference
        crf = crf(last_reference, 100, conn.crf)

        %{
          conn
          | last_reference: time,
            crf: crf,
            conn_state: :active,
            used_by: [waiting | conn.used_by]
        }
      end)

    state = put_in(state.conns[key], %{conn | conn: conn_pid, gun_state: :up, awaited_by: []})

    {:noreply, state}
  end

  @impl true
  def handle_cast({:checkout, conn_pid, pid}, state) do
    state =
      with true <- Process.alive?(conn_pid),
           {key, conn} <- find_conn(state.conns, conn_pid),
           used_by <- List.keydelete(conn.used_by, pid, 0) do
        conn_state = if used_by == [], do: :idle, else: :active

        put_in(state.conns[key], %{conn | conn_state: conn_state, used_by: used_by})
      else
        false ->
          Logger.debug("checkout for closed conn #{inspect(conn_pid)}")
          state

        nil ->
          Logger.debug("checkout for alive conn #{inspect(conn_pid)}, but is not in state")
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:remove_conn, key}, state) do
    conn = state.conns[key]
    Enum.each(conn.awaited_by, fn waiting -> GenServer.reply(waiting, nil) end)
    state = put_in(state.conns, Map.delete(state.conns, key))
    {:noreply, state}
  end

  @impl true
  def handle_call({:checkin, uri, opts, name}, from, state) do
    key = "#{uri.scheme}:#{uri.host}:#{uri.port}"

    case state.conns[key] do
      %{conn: pid, gun_state: :up} = conn ->
        time = :os.system_time(:second)
        last_reference = time - conn.last_reference
        crf = crf(last_reference, 100, conn.crf)

        state =
          put_in(state.conns[key], %{
            conn
            | last_reference: time,
              crf: crf,
              conn_state: :active,
              used_by: [from | conn.used_by]
          })

        {:reply, pid, state}

      %{gun_state: :down} ->
        {:reply, nil, state}

      %{gun_state: :init} = conn ->
        state = put_in(state.conns[key], %{conn | awaited_by: [from | conn.awaited_by]})
        {:noreply, state}

      nil ->
        state =
          put_in(state.conns[key], %Conn{
            awaited_by: [from]
          })

        Task.start(Conn, :open, [uri, name, opts])
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call(:refresh, _from, state) do
    {:reply, :ok, put_in(state.conns, %{})}
  end

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, Enum.count(state.conns), state}
  end

  @impl true
  def handle_call(:unused_conns, _from, state) do
    unused_conns =
      state.conns
      |> Enum.filter(&idle_conn?/1)
      |> Enum.sort(&least_used/2)

    {:reply, unused_conns, state}
  end

  defp idle_conn?({_, %{conn_state: :idle}}), do: true
  defp idle_conn?(_), do: false

  defp least_used({_, c1}, {_, c2}) do
    c1.crf <= c2.crf and c1.last_reference <= c2.last_reference
  end

  @impl true
  def handle_info({:gun_up, conn_pid, _protocol}, state) do
    %{origin_host: host, origin_scheme: scheme, origin_port: port} = Gun.info(conn_pid)

    host =
      case :inet.ntoa(host) do
        {:error, :einval} -> host
        ip -> ip
      end

    key = "#{scheme}:#{host}:#{port}"

    state =
      with {key, conn} <- find_conn(state.conns, conn_pid, key),
           {true, key} <- {Process.alive?(conn_pid), key} do
        conn_state = if conn.used_by == [], do: :idle, else: :active

        put_in(state.conns[key], %{
          conn
          | gun_state: :up,
            conn_state: conn_state,
            retries: 0
        })
      else
        {false, key} ->
          put_in(
            state.conns,
            Map.delete(state.conns, key)
          )

        nil ->
          :ok = Gun.close(conn_pid)

          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_down, conn_pid, _protocol, _reason, _killed}, state) do
    retries = Config.get([:connections_pool, :retry], 1)
    # we can't get info on this pid, because pid is dead
    state =
      with {key, conn} <- find_conn(state.conns, conn_pid),
           {true, key} <- {Process.alive?(conn_pid), key} do
        if conn.retries == retries do
          :ok = Gun.close(conn.conn)

          put_in(
            state.conns,
            Map.delete(state.conns, key)
          )
        else
          put_in(state.conns[key], %{
            conn
            | gun_state: :down,
              conn_state: :idle,
              retries: conn.retries + 1
          })
        end
      else
        {false, key} ->
          put_in(
            state.conns,
            Map.delete(state.conns, key)
          )

        nil ->
          Logger.debug(":gun_down for conn which isn't found in state")

          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, conn_pid, reason}, state) do
    Logger.debug("received DOWN message for #{inspect(conn_pid)} reason -> #{inspect(reason)}")

    state =
      with {key, conn} <- find_conn(state.conns, conn_pid) do
        Enum.each(conn.used_by, fn {pid, _ref} ->
          Process.exit(pid, reason)
        end)

        put_in(
          state.conns,
          Map.delete(state.conns, key)
        )
      else
        nil ->
          Logger.debug(":DOWN for conn which isn't found in state")

          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:close_idle_conns, max_idle_time}, state) do
    closing_time = :os.system_time(:second) - max_idle_time

    idle_conns_keys =
      state.conns
      |> Enum.filter(&idle_more_than?(&1, closing_time))
      |> Enum.map(fn {key, %{conn: conn}} ->
        Gun.close(conn)
        key
      end)

    schedule_close_idle_conns()
    {:noreply, put_in(state.conns, Map.drop(state.conns, idle_conns_keys))}
  end

  defp schedule_close_idle_conns do
    max_idle_time = Config.get([:connections_pool, :max_idle_time], 1) * 60
    interval = Config.get([:connections_pool, :closing_idle_conns_interval], 1) * 60 * 1000
    Process.send_after(self(), {:close_idle_conns, max_idle_time}, interval)
  end

  defp idle_more_than?(
         {_, %{conn_state: :idle, last_reference: idle_since}},
         closing_time
       )
       when closing_time >= idle_since do
    true
  end

  defp idle_more_than?(_, _), do: false

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

  def crf(current, steps, crf) do
    1 + :math.pow(0.5, current / steps) * crf
  end
end
