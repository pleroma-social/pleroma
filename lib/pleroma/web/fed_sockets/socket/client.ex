# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.Socket.Client do
  use GenServer

  require Logger

  alias Pleroma.Web.ActivityPub.InternalFetchActor
  alias Pleroma.Web.FedSockets
  alias Pleroma.Web.FedSockets.FedRegistry
  alias Pleroma.Web.FedSockets.FedSocket
  alias Pleroma.Web.FedSockets.Socket
  alias Pleroma.Web.FedSockets.SocketInfo

  @behaviour Socket

  @impl true
  def fetch(%{pid: handler_pid}, data, timeout) do
    GenServer.call(handler_pid, {:fetch, data}, timeout)
  end

  @impl true
  def publish(socket_info, data) do
    send_json(socket_info, %{action: :publish, data: data})
  end

  def start_link(uri) do
    GenServer.start_link(__MODULE__, %{uri: uri})
  end

  @impl true
  def handle_call(
        {:fetch, data},
        from,
        %{
          last_fetch_id: last_fetch_id,
          socket_info: socket_info,
          waiting_fetches: waiting_fetches
        } = state
      ) do
    last_fetch_id = last_fetch_id + 1
    request = %{action: :fetch, data: data, uuid: last_fetch_id}
    socket_info = send_json(socket_info, request)
    waiting_fetches = Map.put(waiting_fetches, last_fetch_id, from)

    {:noreply,
     %{
       state
       | socket_info: socket_info,
         waiting_fetches: waiting_fetches,
         last_fetch_id: last_fetch_id
     }}
  end

  defp send_json(%{conn_pid: conn_pid} = socket_info, data) do
    socket_info = SocketInfo.touch(socket_info)
    :gun.ws_send(conn_pid, {:text, Jason.encode!(data)})
    socket_info
  end

  @impl true
  def init(%{uri: uri}) do
    case initiate_connection(uri) do
      {:ok, ws_origin, conn_pid} ->
        {:ok, socket_info} = FedRegistry.add_fed_socket(ws_origin, conn_pid)
        {:ok, %{socket_info: socket_info, waiting_fetches: %{}, last_fetch_id: 0}}

      {:error, reason} ->
        Logger.debug("Outgoing connection failed - #{inspect(reason)}")
        :ignore
    end
  end

  @impl true
  def handle_info(
        {:gun_ws, _conn_pid, _ref, {:text, raw_message}},
        %{socket_info: socket_info} = state
      ) do
    socket_info = SocketInfo.touch(socket_info)

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
              case Socket.process_message(socket_info, message) do
                :noreply -> :noop
                {:reply, data} -> send_json(socket_info, data)
              end

              state
          end

        {:error, _e} ->
          state
      end

    {:noreply, %{state | socket_info: socket_info}}
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

  def initiate_connection(uri) do
    ws_uri =
      uri
      |> SocketInfo.origin()
      |> FedSockets.uri_for_origin()

    %{host: host, port: port, path: path} = URI.parse(ws_uri)

    with {:ok, conn_pid} <- :gun.open(to_charlist(host), port, %{protocols: [:http]}),
         {:ok, _} <- :gun.await_up(conn_pid),
         # TODO: nodeinfo-based support detection
         #         reference <- :gun.get(conn_pid, to_charlist(path)),
         #         {:response, :fin, 204, _} <- :gun.await(conn_pid, reference) |> IO.inspect(),
         #         :ok <- :gun.flush(conn_pid),
         headers <- build_headers(uri),
         ref <- :gun.ws_upgrade(conn_pid, to_charlist(path), headers, %{silence_pings: false}) do
      receive do
        {:gun_upgrade, ^conn_pid, ^ref, [<<"websocket">>], _} ->
          {:ok, ws_uri, conn_pid}

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
