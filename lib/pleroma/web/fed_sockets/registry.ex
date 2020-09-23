defmodule Pleroma.Web.FedSockets.Registry.Value do
  defstruct [:adapter, :adapter_state]
end

defmodule Pleroma.Web.FedSockets.Registry do
  alias Pleroma.Web.FedSockets.Adapter
  alias Pleroma.Web.FedSockets.Registry.Value

  @registry __MODULE__

  @spec fetch(binary()) :: {:ok, term()} | {:error, term()}
  def fetch(object_id) do
    case get_socket(object_id) do
      {:ok, pid, %Value{adapter: adapter, adapter_state: adapter_state}} ->
        Adapter.fetch(pid, adapter, adapter_state, object_id, 5_000)

      e ->
        e
    end
  end

  @spec publish(binary(), term()) :: :ok | {:error, term()}
  def publish(inbox, data) do
    case get_socket(inbox) do
      {:ok, pid, %Value{adapter: adapter, adapter_state: adapter_state}} ->
        Adapter.publish(pid, adapter, adapter_state, data, 5_000)
        |> IO.inspect(label: "publish reply")

      e ->
        e
    end
  end

  @doc "Get a registry key from a URI. For internal use by adapters."
  @spec key_from_uri(URI.t()) :: String.t()
  def key_from_uri(%URI{scheme: scheme, host: host, port: port}), do: "#{scheme}:#{host}:#{port}"

  @client_adapter Pleroma.Web.FedSockets.Adapter.Gun
  defp get_socket(%URI{} = uri) do
    key = key_from_uri(uri)

    case Registry.lookup(@registry, key) do
      [] ->
        case DynamicSupervisor.start_child(
               Pleroma.Web.FedSockets.ClientSupervisor,
               {@client_adapter, [key, uri]}
             ) do
          {:ok, pid} ->
            {:ok, pid, %Value{adapter: @client_adapter, adapter_state: %{}}}

          {:error, {:already_started, pid}} ->
            {:ok, pid, %Value{adapter: @client_adapter, adapter_state: %{}}}

          {:error, _} = e ->
            e

          e ->
            {:error, e}
        end

      [{pid, value}] ->
        {:ok, pid, value}
    end
  end

  defp get_socket(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %{host: nil} = uri -> {:error, {:invalid_uri, uri}}
      %{port: nil} = uri -> {:error, {:invalid_uri, uri}}
      %{scheme: nil} = uri -> {:error, {:invalid_uri, uri}}
      uri -> get_socket(uri)
    end
  end
end
