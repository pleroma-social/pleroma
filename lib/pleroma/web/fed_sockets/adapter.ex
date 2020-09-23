defmodule Pleroma.Web.FedSockets.Adapter do
  @moduledoc """
   A behavior both types of sockets (server and client) should implement
   and a collection of helper functions useful to both
  """

  @type adapter_state :: map()

  @doc """
    Send a message through the socket and wait for answer.
    Accepts a non-encoded message payload, except the uuid, it will be added automatically.
  """

  @callback request(pid(), adapter_state(), map(), timeout()) :: {:ok, term()} | {:error, term()}

  alias Pleroma.Object
  alias Pleroma.Object.Containment
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ObjectView
  alias Pleroma.Web.ActivityPub.UserView
  alias Pleroma.Web.ActivityPub.Visibility
  alias Pleroma.Web.Federator

  @spec fetch(pid(), module(), adapter_state(), term(), timeout()) ::
          {:ok, term()} | {:error, term()}
  def fetch(pid, adapter, adapter_state, id, timeout) do
    data = %{action: :fetch, data: id}
    apply(adapter, :request, [pid, adapter_state, data, timeout])
  end

  @spec publish(pid(), module(), adapter_state(), term(), timeout()) ::
          {:ok, term()} | {:error, term()}
  def publish(pid, adapter, adapter_state, data, timeout) do
    data = %{action: :publish, data: data}
    apply(adapter, :request, [pid, adapter_state, data, timeout])
  end

  @type origin :: String.t()
  @type fetch_id :: integer()
  @type waiting_requests :: %{required(fetch_id()) => pid()}
  @doc "Processes incoming messages. Returns {:reply, websocket_frame,waiting_requests} or `{:noreply,waiting_requests}`"
  @spec process_message(binary() | map(), origin(), waiting_requests()) ::
          {:reply, term(), waiting_requests()} | {:noreply, waiting_requests()}
  def process_message(message, origin, waiting_requests) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, message} -> do_process_message(message, origin, waiting_requests)
      # 1003 indicates that an endpoint is terminating the connection
      # because it has received a type of data it cannot accept. 
      {:error, decode_error} -> {:reply, {:close, 1003, Exception.message(decode_error)}}
    end
  end

  def process_message(message, origin, waiting_requests),
    do: do_process_message(message, origin, waiting_requests)

  defp do_process_message(
         %{"action" => "publish", "data" => data, "uuid" => uuid},
         origin,
         waiting_requests
       ) do
    if Containment.contain_origin(origin, data) do
      Federator.incoming_ap_doc(data)
    end

    data = %{
      "action" => "reply",
      "uuid" => uuid,
      "data" => "ok"
    }

    {:reply, {:text, Jason.encode!(data)}, waiting_requests}
  end

  defp do_process_message(
         %{"action" => "fetch", "uuid" => uuid, "data" => ap_id},
         _,
         waiting_requests
       ) do
    data = %{
      "action" => "reply",
      "uuid" => uuid,
      "data" => represent_item(ap_id)
    }

    {:reply, {:text, Jason.encode!(data)}, waiting_requests}
  end

  defp do_process_message(
         %{"action" => "reply", "uuid" => uuid, "data" => data},
         _,
         waiting_requests
       ) do
    with {pid, waiting_requests} when is_pid(pid) <- Map.pop(waiting_requests, uuid) do
      send(pid, {:request_reply, uuid, data})
      {:noreply, waiting_requests}
    else
      _ ->
        {:noreply, waiting_requests}
    end
  end

  defp do_process_message(_, _, waiting_requests) do
    {:reply, {:close, 1003, "Unknown message type."}, waiting_requests}
  end

  defp represent_item(ap_id) do
    case User.get_by_ap_id(ap_id) do
      nil ->
        object = Object.get_cached_by_ap_id(ap_id)

        if Visibility.is_public?(object) do
          Phoenix.View.render(ObjectView, "object.json", object: object)
        else
          nil
        end

      user ->
        Phoenix.View.render(UserView, "user.json", user: user)
    end
  end
end
