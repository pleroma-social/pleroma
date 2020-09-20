# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.Socket.Server do
  require Logger

  alias Pleroma.Web.FedSockets.Socket
  alias Pleroma.Web.FedSockets.FedRegistry
  alias Pleroma.Web.FedSockets.FedSocket
  alias Pleroma.Web.FedSockets.SocketInfo

  import HTTPSignatures, only: [validate_conn: 1, split_signature: 1]

  require Logger

  @behaviour :cowboy_websocket
  @behaviour Socket

  @impl true
  def fetch(_socket, _data, _timeout), do: {:error, :not_implemented}

  @impl true
  def publish(_socket, _data), do: {:error, :not_implemented}

  @impl true
  def init(req, state) do
    shake = FedSocket.shake()

    with true <- Pleroma.Config.get([:fed_sockets, :enabled]),
         sec_protocol <- :cowboy_req.header("sec-websocket-protocol", req, nil),
         headers = %{"(request-target)" => ^shake} <- :cowboy_req.headers(req),
         true <- validate_conn(%{req_headers: headers}),
         %{"keyId" => origin} <- split_signature(headers["signature"]) do
      req =
        if is_nil(sec_protocol) do
          req
        else
          :cowboy_req.set_resp_header("sec-websocket-protocol", sec_protocol, req)
        end

      {:cowboy_websocket, req, %{origin: origin}, %{}}
    else
      e ->
        Logger.debug(fn -> "#{__MODULE__}: Websocket switch failed, #{inspect(e)}" end)
        {:ok, req, state}
    end
  end

  @impl true
  def websocket_init(%{origin: origin}) do
    case FedRegistry.add_fed_socket(origin) do
      {:ok, socket_info} ->
        {:ok, socket_info}

      e ->
        Logger.error("FedSocket websocket_init failed - #{inspect(e)}")
        {:error, inspect(e)}
    end
  end

  @impl true
  def websocket_handle(:ping, socket_info), do: {:ok, socket_info}

  def websocket_handle({:text, raw_message}, socket_info) do
    socket_info = SocketInfo.touch(socket_info)

    case Jason.decode(raw_message) do
      {:ok, message} ->
        case message do
          message ->
            case Socket.process_message(socket_info, message) do
              :noreply -> {:ok, socket_info}
              {:reply, data} -> {:reply, Jason.encode!(data), socket_info}
            end
        end

      {:error, decode_error} ->
        exit({:malformed_message, decode_error})
    end
  end

  def websocket_info({:send, message}, socket_info) do
    socket_info = SocketInfo.touch(socket_info)

    {:reply, {:text, message}, socket_info}
  end

  def websocket_info(:close, state) do
    {:stop, state}
  end

  def websocket_info(message, state) do
    Logger.debug("#{__MODULE__} unknown message #{inspect(message)}")
    {:ok, state}
  end
end
