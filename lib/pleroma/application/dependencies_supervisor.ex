# # Pleroma: A lightweight social networking server
# # Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# # SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.DependenciesSupervisor do
  use DynamicSupervisor

  alias Pleroma.Application.Dependencies
  alias Pleroma.Application.DependenciesState

  require Logger

  @type child() ::
          Supervisor.child_spec()
          | {module(), term()}
          | module()

  @type child_type() :: :static | :dynamic

  def start_link(_), do: DynamicSupervisor.start_link(__MODULE__, :no_arg, name: __MODULE__)

  @impl true
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec start_children([:supervisor.child_spec() | module()], child_type()) ::
          :ok | {:error, {:already_started, pid()} | :max_children | term()}
  def start_children(children, :static) do
    start_while(children, &start_static_child/1)
  end

  def start_children(children, :dynamic) do
    start_while(children, &start_dynamic_child/1)
  end

  defp start_while(children, fun) do
    Enum.reduce_while(children, :ok, fn child, acc ->
      case fun.(child) do
        {:ok, _} ->
          {:cont, acc}

        # consider this behavior is normal
        :ignore ->
          Logger.info("#{inspect(child)} is ignored.")
          {:cont, acc}

        error ->
          Logger.error("Child #{inspect(child)} can't be started. #{inspect(error)}")
          {:halt, error}
      end
    end)
  end

  defp start_static_child(child) do
    DynamicSupervisor.start_child(__MODULE__, child)
  end

  defp start_dynamic_child(child) do
    with {:ok, relations} <- Dependencies.find_relations(child),
         {:ok, pid} <- DynamicSupervisor.start_child(__MODULE__, spec(child)) do
      Enum.each(relations, fn {key, _} ->
        DependenciesState.put_pid(key, pid)
      end)

      {:ok, pid}
    end
  end

  defp spec(Oban), do: {Oban, Pleroma.Config.get(Oban)}

  defp spec(Pleroma.Web.StreamerRegistry) do
    {Registry,
     [
       name: Pleroma.Web.Streamer.registry(),
       keys: :duplicate,
       partitions: System.schedulers_online()
     ]}
  end

  defp spec(child), do: child

  @spec put_paths([any()]) :: :ok
  def put_paths([]), do: :ok

  def put_paths(paths), do: DependenciesState.put_paths(paths)

  @spec need_reboot?() :: boolean()
  def need_reboot?, do: DependenciesState.paths() != []

  @spec restart_children() :: :ok
  def restart_children do
    DependenciesState.get_and_reset_paths()
    |> Enum.reduce_while(:ok, fn path, acc ->
      case restart_child(path) do
        {:ok, _} ->
          {:cont, acc}

        :ignore ->
          Logger.info("path #{inspect(path)} is ignored.")
          {:cont, acc}

        error ->
          {:halt, error}
      end
    end)
  end

  defp restart_child(path) do
    path
    |> DependenciesState.pid()
    |> restart_child(path)
  end

  defp restart_child(nil, path) do
    # child wasn't started yet
    with {_, module} <- Dependencies.find_relation(path) do
      start_dynamic_child(module)
    end
  end

  defp restart_child(pid, path) when is_pid(pid) do
    # main module can have multiple keys
    # first we search for main module
    with {_, module} <- Dependencies.find_relation(path),
         :ok <- terminate(pid, module),
         # then we search for mappings, which depends on this main module
         {:ok, relations} <- Dependencies.find_relations(module) do
      Enum.each(relations, fn {key, _} ->
        DependenciesState.delete_pid(key)
      end)

      start_dynamic_child(module)
    else
      error ->
        Logger.warn(
          "Child can't be restarted. PID - #{inspect(pid)}, path - #{inspect(path)} #{
            inspect(error)
          }"
        )

        error
    end
  end

  defp terminate(pid, module) do
    with {:error, :not_found} <- DynamicSupervisor.terminate_child(__MODULE__, pid),
         # maybe child was restarted and pid wasn't updated in Agent, trying to find by module
         pid when not is_nil(pid) <- Process.whereis(module) do
      DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end
end
