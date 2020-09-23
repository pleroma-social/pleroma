defmodule Pleroma.Web.FedSockets.Adapter do
  @moduledoc """
   A behavior both types of sockets (server and client) should implement
   and a collection of helper functions useful to both
  """

  @type adapter_state :: map()

  @doc "A synchronous fetch."
  @callback fetch(pid(), adapter_state(), term(), timeout()) :: {:ok, term()} | {:error, term()}

  @doc "An asynchronous publish."
  @callback publish(pid(), adapter_state(), term()) :: :ok | {:error, term()}

  alias Pleroma.Object
  alias Pleroma.Object.Containment
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ObjectView
  alias Pleroma.Web.ActivityPub.UserView
  alias Pleroma.Web.ActivityPub.Visibility
  alias Pleroma.Web.Federator

  @type origin :: String.t()
  @type fetch_id :: integer()
  @type waiting_fetches :: %{required(fetch_id()) => pid()}
  @doc "Processes incoming messages. Returns {:reply, websocket_frame, waiting_fetches} or `{:noreply, waiting_fetches}`"
  @spec process_message(binary() | map(), origin(), waiting_fetches()) ::
          {:reply, term(), waiting_fetches()} | {:noreply, waiting_fetches()}
  def process_message(message, origin, waiting_fetches) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, message} -> do_process_message(message, origin, waiting_fetches)
      # 1003 indicates that an endpoint is terminating the connection
      # because it has received a type of data it cannot accept. 
      {:error, decode_error} -> {:reply, {:close, 1003, Exception.message(decode_error)}}
    end
  end

  def process_message(message, origin, waiting_fetches),
    do: do_process_message(message, origin, waiting_fetches)

  defp do_process_message(%{"action" => "publish", "data" => data}, origin, waiting_fetches) do
    if Containment.contain_origin(origin, data) do
      Federator.incoming_ap_doc(data)
    end

    {:noreply, waiting_fetches}
  end

  defp do_process_message(
         %{"action" => "fetch", "uuid" => uuid, "data" => ap_id},
         _,
         waiting_fetches
       ) do
    data = %{
      "action" => "fetch_reply",
      "status" => "processed",
      "uuid" => uuid,
      "data" => represent_item(ap_id)
    }

    {:reply, {:text, Jason.encode!(data)}, waiting_fetches}
  end

  defp do_process_message(
         %{"action" => "fetch_reply", "uuid" => uuid, "data" => data},
         _,
         waiting_fetches
       ) do
    with {pid, waiting_fetches} when is_pid(pid) <- Map.pop(waiting_fetches, uuid) do
      send(pid, {:fetch_reply, uuid, data})
      {:noreply, waiting_fetches}
    else
      _ ->
        {:noreply, waiting_fetches}
    end
  end

  defp do_process_message(_, _, waiting_fetches) do
    {:reply, {:close, 1003, "Unknown message type."}, waiting_fetches}
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
