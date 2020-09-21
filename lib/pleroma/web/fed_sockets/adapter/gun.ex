# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.Adapter.Gun do
  use GenServer, restart: :temporary

  require Logger

  alias Pleroma.Web.ActivityPub.InternalFetchActor
  alias Pleroma.Web.FedSockets.Registry.Value
  alias Pleroma.Web.FedSockets.FedSocket
  alias Pleroma.Web.FedSockets.Adapter

  @behaviour Adapter

  @registry Pleroma.Web.FedSockets.Registry

  @impl true
  def fetch(pid, state, id, timeout) do
    # TODO: refactor with atomics and encoding on the client
    with {:ok, _} <- await_connected(pid, state) do
      GenServer.call(pid, {:fetch, id}, timeout)
    end
  end

  @impl true
  def publish(pid, state, data) do
    with {:ok, conn_pid} <- await_connected(pid, state) do
      send_json(conn_pid, %{action: :publish, data: data})
    end
  end

  defp await_connected(_pid, %{conn_pid: conn_pid}), do: {:ok, conn_pid}

  defp await_connected(pid, _) do
    monitor = Process.monitor(pid)
    GenServer.cast(pid, {:await_connected, self()})

    receive do
      {:DOWN, ^monitor, _, _, {:shutdown, reason}} -> reason
      {:DOWN, ^monitor, _, _, reason} -> {:error, reason}
      {:await_connected, ^pid, conn_pid} -> {:ok, conn_pid}
    end
  end

  def start_link([key | _] = opts) do
    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {@registry, key, %Value{adapter: __MODULE__, adapter_state: %{}}}}
    )
  end

  @impl true
  def init(opts) do
    {:ok, nil, {:continue, {:connect, opts}}}
  end

  @impl true
  def handle_continue({:connect, [key, uri] = opts}, _) do
    case initiate_connection(uri) do
      {:ok, conn_pid} ->
        Registry.update_value(@registry, key, fn value ->
          %{value | adapter_state: %{conn_pid: conn_pid}}
        end)

        {:noreply,
         %{conn_pid: conn_pid, waiting_fetches: %{}, last_fetch_id: 0, origin: uri, key: key}}

      {:error, reason} = e ->
        Logger.debug("Outgoing connection failed - #{inspect(reason)}")
        {:stop, {:shutdown, e}, opts}
    end
  end

  @impl true
  def handle_cast({:await_connected, pid}, %{conn_pid: conn_pid} = state) do
    send(pid, {:await_connected, self(), conn_pid})
    {:noreply, state}
  end

  @impl true
  def handle_call(
        {:fetch, data},
        from,
        %{
          last_fetch_id: last_fetch_id,
          conn_pid: conn_pid,
          waiting_fetches: waiting_fetches
        } = state
      ) do
    last_fetch_id = last_fetch_id + 1
    request = %{action: :fetch, data: data, uuid: last_fetch_id}
    :ok = send_json(conn_pid, request)
    waiting_fetches = Map.put(waiting_fetches, last_fetch_id, from)

    {:noreply,
     %{
       state
       | waiting_fetches: waiting_fetches,
         last_fetch_id: last_fetch_id
     }}
  end

  defp send_json(conn_pid, data) do
    :gun.ws_send(conn_pid, {:text, Jason.encode!(data)})
  end

  @impl true
  def handle_info(
        {:gun_ws, _conn_pid, _ref, {:text, raw_message}},
        %{conn_pid: conn_pid, origin: origin} = state
      ) do
    state =
      case Jason.decode(raw_message) do
        {:ok, message} ->
          case message do
            %{"action" => "fetch_reply", "uuid" => uuid, "data" => data} ->
              with {{_, _} = client, waiting_fetches} <- Map.pop(state.waiting_fetches, uuid) do
                GenServer.reply(client, {:ok, data})
                %{state | waiting_fetches: waiting_fetches}
              else
                _ ->
                  state
              end

            message ->
              case Adapter.process_message(message, origin) do
                :noreply -> :noop
                {:reply, data} -> send_json(conn_pid, data)
              end

              state
          end

        {:error, decode_error} ->
          exit({:malformed_message, decode_error})
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:close, state) do
    Logger.debug("Sending close frame !!!!!!!")
    {:close, state}
  end

  @impl true
  def handle_info({:gun_down, _pid, _prot, :closed, _}, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:gun_ws, _, _, :pong}, state) do
    {:noreply, state, :hibernate}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("#{__MODULE__} unhandled event #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "#{__MODULE__} terminating outgoing connection for #{inspect(state)} for #{inspect(reason)}"
    )

    {:ok, state}
  end

  @path '/api/fedsocket/v1'
  def initiate_connection(uri) do
    %{host: host, port: port} = URI.parse(uri)

    with {:ok, conn_pid} <- :gun.open(to_charlist(host), port, %{protocols: [:http]}),
         {:ok, _} <- :gun.await_up(conn_pid),
         # TODO: nodeinfo-based support detection
         #         reference <- :gun.get(conn_pid, to_charlist(path)),
         #         {:response, :fin, 204, _} <- :gun.await(conn_pid, reference) |> IO.inspect(),
         #         :ok <- :gun.flush(conn_pid),
         headers <- build_headers(uri),
         ref <- :gun.ws_upgrade(conn_pid, @path, headers, %{silence_pings: false}) do
      receive do
        {:gun_upgrade, ^conn_pid, ^ref, [<<"websocket">>], _} ->
          {:ok, conn_pid}

          #        mes ->
          #          IO.inspect(mes)
      after
        15_000 ->
          Logger.debug("Fedsocket timeout connecting to #{inspect(uri)}")
          {:error, :timeout}
      end
    else
      {:response, :nofin, 404, _} ->
        {:error, :fedsockets_not_supported}

      e ->
        Logger.debug("Fedsocket error connecting to #{inspect(uri)}")
        {:error, e}
    end
  end

  defp build_headers(uri) do
    host_for_sig = uri |> URI.parse() |> host_signature()

    shake = FedSocket.shake()
    digest = "SHA-256=" <> (:crypto.hash(:sha256, shake) |> Base.encode64())
    date = Pleroma.Signature.signed_date()
    shake_size = byte_size(shake)

    signature_opts = %{
      "(request-target)": shake,
      "content-length": to_charlist("#{shake_size}"),
      date: date,
      digest: digest,
      host: host_for_sig
    }

    signature = Pleroma.Signature.sign(InternalFetchActor.get_actor(), signature_opts)

    [
      {"signature", signature},
      {"date", date},
      {"digest", digest},
      {"content-length", to_string(shake_size)},
      {"(request-target)", shake}
    ]
  end

  defp host_signature(%{host: host, scheme: scheme, port: port}) do
    if port == URI.default_port(scheme) do
      host
    else
      "#{host}:#{port}"
    end
  end
end
