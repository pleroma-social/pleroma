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
  def request(pid, state, message, timeout) do
    with {:ok, conn_pid, last_request_id_ref} <- await_connected(pid, state) do
      request_id = :atomics.add_get(last_request_id_ref, 1, 1)
      message = Map.put(message, :uuid, request_id)
      send(pid, {:register_request, request_id, self()})
      send_json(conn_pid, message)

      receive do
        {:request_reply, ^request_id, data} -> {:ok, data}
      after
        timeout -> {:error, :timeout}
      end
    end
  end

  defp await_connected(_pid, %{conn_pid: conn_pid, last_request_id_ref: last_request_id_ref}),
    do: {:ok, conn_pid, last_request_id_ref}

  defp await_connected(pid, _) do
    monitor = Process.monitor(pid)
    GenServer.cast(pid, {:await_connected, self()})

    receive do
      {:DOWN, ^monitor, _, _, reason} ->
        {:error, reason}

      {:await_connected, ^pid, conn_pid, last_request_id_ref} ->
        {:ok, conn_pid, last_request_id_ref}
    end
  end

  def start_link([key | _] = opts) do
    last_request_id_ref = :atomics.new(1, [])
    :ok = :atomics.put(last_request_id_ref, 1, 0)

    GenServer.start_link(__MODULE__, [last_request_id_ref | opts],
      name:
        {:via, Registry,
         {@registry, key,
          %Value{adapter: __MODULE__, adapter_state: %{last_request_id_ref: last_request_id_ref}}}}
    )
  end

  @impl true
  def init(opts) do
    {:ok, nil, {:continue, {:connect, opts}}}
  end

  @impl true
  def handle_continue({:connect, [last_request_id_ref, key, uri] = opts}, _) do
    case initiate_connection(uri) do
      {:ok, conn_pid} ->
        Registry.update_value(@registry, key, fn value ->
          %{value | adapter_state: Map.put(value.adapter_state, :conn_pid, conn_pid)}
        end)

        {:noreply,
         %{
           conn_pid: conn_pid,
           waiting_requests: %{},
           last_request_id_ref: last_request_id_ref,
           origin: uri,
           key: key
         }}

      {:error, reason} = e ->
        Logger.debug("Outgoing connection failed - #{inspect(reason)}")
        {:stop, {:shutdown, e}, opts}
    end
  end

  @impl true
  def handle_cast(
        {:await_connected, pid},
        %{conn_pid: conn_pid, last_request_id_ref: last_request_id_ref} = state
      ) do
    send(pid, {:await_connected, self(), conn_pid, last_request_id_ref})
    {:noreply, state}
  end

  defp send_json(conn_pid, data) do
    :gun.ws_send(conn_pid, {:text, Jason.encode!(data)})
  end

  @impl true
  def handle_info(
        {:register_request, request_id, pid},
        %{waiting_requests: waiting_requests} = state
      ) do
    waiting_requests = Map.put(waiting_requests, request_id, pid)
    {:noreply, %{state | waiting_requests: waiting_requests}}
  end

  @impl true
  def handle_info(
        {:gun_ws, _conn_pid, _ref, {:text, raw_message}},
        %{conn_pid: conn_pid, origin: origin, waiting_requests: waiting_requests} = state
      ) do
    waiting_requests =
      case Adapter.process_message(raw_message, origin, waiting_requests) do
        {:reply, frame, waiting_requests} ->
          :gun.ws_send(conn_pid, frame)
          waiting_requests

        {:noreply, waiting_requests} ->
          waiting_requests
      end

    {:noreply, %{state | waiting_requests: waiting_requests}}
  end

  @impl true
  def handle_info({:gun_down, conn_pid, _, reason, _}, %{conn_pid: conn_pid} = state) do
    {:stop, reason, state}
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

    with {:ok, conn_pid} <- :gun.open(to_charlist(host), port, %{protocols: [:http], retry: 0}),
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

        {:gun_response, ^conn_pid, _, _, status, _} ->
          {:error, {:ws_upgrade_failed, {:status, status}}}

        {:gun_error, ^conn_pid, ^ref, reason} ->
          {:error, {:ws_upgrade_failed, reason}}

        {:gun_down, ^conn_pid, _, reason, _} ->
          {:error, {:ws_upgrade_failed, reason}}
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
