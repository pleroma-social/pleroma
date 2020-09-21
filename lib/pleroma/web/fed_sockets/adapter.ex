defmodule Pleroma.Web.FedSockets.Adapter do
  @moduledoc """
   A behavior both types of sockets (server and client) should implement
   and a collection of helper functions useful to both.
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
  alias Pleroma.Web.FedSockets.IngesterWorker

  @typedoc """
    Should be "fetch" or "publish"
  """
  @type common_action :: String.t()
  @type origin :: String.t()
  @doc "Process non adapter-specific messages."
  @spec process_message(map(), origin()) ::
          {:reply, term()} | :noreply | {:error, :unknown_action}
  def process_message(%{"action" => "publish", "data" => data}, origin) do
    if Containment.contain_origin(origin, data) do
      IngesterWorker.enqueue("ingest", %{"object" => data})
    end

    :noreply
  end

  def process_message(%{"action" => "fetch", "uuid" => uuid, "data" => ap_id}, _) do
    data = %{
      "action" => "fetch_reply",
      "status" => "processed",
      "uuid" => uuid,
      "data" => represent_item(ap_id)
    }

    {:reply, data}
  end

  def process_message(_, _) do
    {:error, :unknown_action}
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
