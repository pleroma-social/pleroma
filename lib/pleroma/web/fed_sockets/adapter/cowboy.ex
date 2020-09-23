# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.Adapter.Cowboy do
  require Logger

  alias Pleroma.Web.FedSockets.Adapter
  alias Pleroma.Web.FedSockets.FedSocket
  alias Pleroma.Web.FedSockets.Registry.Value

  import HTTPSignatures, only: [validate_conn: 1, split_signature: 1]

  require Logger

  @behaviour :cowboy_websocket
  @behaviour Adapter

  @impl true
  def request(pid, %{last_request_id_ref: last_request_id_ref}, message, timeout) do
    request_id = :atomics.add_get(last_request_id_ref, 1, 1)
    message = Map.put(message, :uuid, request_id)
    send(pid, {:send_request, Jason.encode!(message), request_id, self()})

    receive do
      {:request_reply, ^request_id, data} -> {:ok, data}
    after
      timeout -> {:error, :timeout}
    end
  end

  @impl true
  def init(req, state) do
    shake = FedSocket.shake()

    with {_, true} <- {:enabled, Pleroma.Config.get([:fed_sockets, :enabled])},
         sec_protocol <- :cowboy_req.header("sec-websocket-protocol", req, nil),
         {_, %{"(request-target)" => ^shake} = headers} <-
           {:has_request_target, :cowboy_req.headers(req)},
         {_, true} <- {:signature_validated, validate_conn(%{req_headers: headers})},
         %{"keyId" => origin} <- split_signature(headers["signature"]) do
      req =
        if is_nil(sec_protocol) do
          req
        else
          :cowboy_req.set_resp_header("sec-websocket-protocol", sec_protocol, req)
        end

      {:cowboy_websocket, req, origin, %{}}
    else
      {:has_request_target, headers} ->
        Logger.debug(fn ->
          "#{__MODULE__}: Wrong or no \"(request-target)\" header. Rejecting websocket switch. Headers:\n#{
            inspect(headers)
          }"
        end)

        :cowboy_req.reply(400, req)
        {:ok, req, state}

      {:signature_validated, false} ->
        Logger.debug(fn ->
          "#{__MODULE__}: Signature validation failed. Rejecting websocket switch."
        end)

        :cowboy_req.reply(401, req)
        {:ok, req, state}

      e ->
        Logger.debug(fn -> "#{__MODULE__}: Websocket switch failed, #{inspect(e)}" end)
        :cowboy_req.reply(500, req)
        {:ok, req, state}
    end
  end

  @registry Pleroma.Web.FedSockets.Registry

  @impl true
  def websocket_init(origin) do
    key = Pleroma.Web.FedSockets.Registry.key_from_uri(URI.parse(origin))
    # Since, unlike with gun, we don't have calls.
    # We store last fetch id in an atomic counter and use casts.
    last_request_id_ref = :atomics.new(1, [])
    :ok = :atomics.put(last_request_id_ref, 1, 0)

    case Registry.register(@registry, key, %Value{
           adapter: __MODULE__,
           adapter_state: %{last_request_id_ref: last_request_id_ref}
         }) do
      {:ok, _owner} ->
        {:ok, %{origin: origin, waiting_requests: %{}}}

      {:error, {:already_registered, _}} ->
        {:stop, origin}
    end
  end

  @impl true
  def websocket_handle(:ping, state), do: {:ok, state}

  def websocket_handle(
        {:text, raw_message},
        %{origin: origin, waiting_requests: waiting_requests} = state
      ) do
    case Adapter.process_message(raw_message, origin, waiting_requests) do
      {:reply, frame, waiting_requests} ->
        state = %{state | waiting_requests: waiting_requests}
        {:reply, frame, state}

      {:noreply, waiting_requests} ->
        {:ok, %{state | waiting_requests: waiting_requests}}
    end
  end

  @impl true
  def websocket_info(
        {:send_request, message, request_id, pid},
        %{waiting_requests: waiting_requests} = state
      ) do
    waiting_requests = Map.put(waiting_requests, request_id, pid)
    {:reply, {:text, message}, %{state | waiting_requests: waiting_requests}}
  end

  @impl true
  def websocket_info({:send, message}, state) do
    {:reply, {:text, message}, state}
  end

  @impl true
  def websocket_info(:close, state) do
    {:stop, state}
  end

  def websocket_info(message, state) do
    Logger.debug("#{__MODULE__} unknown message #{inspect(message)}")
    {:ok, state}
  end
end
