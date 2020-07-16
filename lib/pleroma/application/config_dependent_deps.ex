# # Pleroma: A lightweight social networking server
# # Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# # SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.ConfigDependentDeps do
  use GenServer

  require Logger

  @config_path_mods_relation [
    {{:pleroma, :chat}, Pleroma.Web.ChatChannel.ChatChannelState},
    {{:pleroma, Oban}, Oban},
    {{:pleroma, :rate_limit}, Pleroma.Web.Plugs.RateLimiter.Supervisor},
    {{:pleroma, :streamer}, Pleroma.Web.Streamer.registry()},
    {{:pleroma, :pools}, Pleroma.Gun.GunSupervisor},
    {{:pleroma, :connections_pool}, Pleroma.Gun.GunSupervisor},
    {{:pleroma, :hackney_pools}, Pleroma.HTTP.HackneySupervisor},
    {{:pleroma, :gopher}, Pleroma.Gopher.Server},
    {{:pleroma, Pleroma.Captcha, [:seconds_valid]}, Pleroma.Web.Endpoint},
    {{:pleroma, Pleroma.Upload, [:proxy_remote]},
     Pleroma.Application.StartUpDependencies.adapter_module()},
    {{:pleroma, :instance, [:upload_limit]}, Pleroma.Web.Endpoint},
    {{:pleroma, :fed_sockets, [:enabled]}, Pleroma.Web.Endpoint},
    {:eshhd, :eshhd},
    {:ex_aws, :ex_aws}
  ]

  def start_link(opts) do
    opts = Keyword.put_new(opts, :relations, @config_path_mods_relation)

    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @impl true
  def init(opts) do
    init_state = %{
      dynamic_supervisor: opts[:dynamic_supervisor],
      relations: opts[:relations],
      reboot_paths: [],
      pids: %{}
    }

    {:ok, init_state}
  end

  def start_dependency(module, server \\ __MODULE__) do
    GenServer.call(server, {:start_dependency, module})
  end

  def need_reboot?(server \\ __MODULE__) do
    GenServer.call(server, :need_reboot?)
  end

  def restart_dependencies(server \\ __MODULE__) do
    GenServer.call(server, :restart_dependencies)
  end

  def clear_state(server \\ __MODULE__) do
    GenServer.call(server, :clear_state)
  end

  def save_config_paths_for_restart(changes, server \\ __MODULE__) do
    GenServer.call(server, {:save_config_paths, changes})
  end

  @impl true
  def handle_call({:start_dependency, module}, _, state) do
    {result, state} =
      with {pid, state} when is_pid(pid) <- start_module(module, state) do
        {{:ok, pid}, state}
      else
        error -> {error, state}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:need_reboot?, _, state) do
    {:reply, state[:reboot_paths] != [], state}
  end

  @impl true
  def handle_call(:restart_dependencies, _, state) do
    {paths, state} = Map.get_and_update(state, :reboot_paths, &{&1, []})
    started_apps = Application.started_applications()

    {result, state} =
      Enum.reduce_while(paths, {:ok, state}, fn
        path, {:ok, acc} when is_tuple(path) ->
          case restart(path, acc, acc[:pids][path], with_terminate: true) do
            {pid, state} when is_pid(pid) ->
              {:cont, {:ok, state}}

            :ignore ->
              Logger.info("path #{inspect(path)} is ignored.")
              {:cont, {:ok, acc}}

            error ->
              {:halt, {error, acc}}
          end

        app, {:ok, acc}
        when is_atom(app) and app not in [:logger, :quack, :pleroma, :prometheus, :postgrex] ->
          restart_app(app, started_apps)
          {:cont, {:ok, acc}}
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call(:clear_state, _, state) do
    state =
      state
      |> Map.put(:reboot_paths, [])
      |> Map.put(:pids, %{})

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:save_config_paths, changes}, _, state) do
    paths =
      Enum.reduce(changes, state[:reboot_paths], fn
        %{group: group, key: key, value: value}, acc ->
          with {path, _} <- find_relation(state[:relations], group, key, value) do
            if path not in acc do
              [path | acc]
            else
              acc
            end
          else
            _ ->
              acc
          end
      end)

    {:reply, paths, put_in(state[:reboot_paths], paths)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    updated_state =
      with {path, ^pid} <-
             Enum.find(state[:pids], fn {_, registered_pid} -> registered_pid == pid end) do
        {_new_pid, new_state} = restart(path, state, pid)
        new_state
      else
        _ -> state
      end

    {:noreply, updated_state}
  end

  defp start_module(module, state) do
    with {:ok, relations} <- find_relations(state[:relations], module) do
      start_module(module, relations, state)
    end
  end

  defp start_module(module, relations, state) do
    spec =
      module
      |> Pleroma.Application.StartUpDependencies.spec()
      |> Supervisor.child_spec(restart: :temporary)

    with {:ok, pid} <-
           DynamicSupervisor.start_child(
             state[:dynamic_supervisor],
             spec
           ) do
      pids = Map.new(relations, fn {path, _} -> {path, pid} end)
      Process.monitor(pid)
      {pid, put_in(state[:pids], Map.merge(state[:pids], pids))}
    end
  end

  defp restart(path, state, pid, opts \\ [])

  defp restart(path, state, nil, _) do
    with {_, module} <- find_relation(state[:relations], path) do
      start_module(module, state)
    end
  end

  defp restart(path, state, pid, opts) when is_pid(pid) do
    with {_, module} <- find_relation(state[:relations], path),
         {:ok, relations} <- find_relations(state[:relations], module) do
      if opts[:with_terminate] do
        :ok = DynamicSupervisor.terminate_child(state[:dynamic_supervisor], pid)
      end

      paths_for_remove = Enum.map(relations, fn {path, _} -> path end)
      state = put_in(state[:pids], Map.drop(state[:pids], paths_for_remove))

      start_module(module, relations, state)
    end
  end

  defp restart_app(app, started_applications) do
    with {^app, _, _} <- List.keyfind(started_applications, app, 0) do
      :ok = Application.stop(app)
      :ok = Application.start(app)
    else
      nil ->
        Logger.info("#{app} is not started.")

      error ->
        error
        |> inspect()
        |> Logger.error()
    end
  end

  defp find_relations(relations, module) do
    case Enum.filter(relations, fn {_, mod} -> mod == module end) do
      [] ->
        {:error, :relations_not_found}

      relations ->
        {:ok, relations}
    end
  end

  defp find_relation(relations, group, key, value) do
    Enum.find(relations, fn
      {g, _} when is_atom(g) ->
        g == group

      {{g, k}, _} ->
        g == group and k == key

      {{g, k, subkeys}, _} ->
        g == group and k == key and Enum.any?(Keyword.keys(value), &(&1 in subkeys))
    end)
  end

  def find_relation(relations, path) do
    with nil <- Enum.find(relations, fn {key, _} -> key == path end) do
      {:error, :relation_not_found}
    end
  end
end
