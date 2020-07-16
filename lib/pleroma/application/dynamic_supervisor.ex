# # Pleroma: A lightweight social networking server
# # Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# # SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.DynamicSupervisor do
  use DynamicSupervisor

  @registry Pleroma.Application.DynamicSupervisor.Registry

  @type child() ::
          Supervisor.child_spec()
          | {module(), term()}
          | module()

  def start_link(_), do: DynamicSupervisor.start_link(__MODULE__, :no_arg, name: __MODULE__)

  @impl true
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec registry() :: module()
  def registry, do: @registry

  @spec start_child(child()) :: DynamicSupervisor.on_start_child()
  def start_child(child), do: DynamicSupervisor.start_child(__MODULE__, child)

  @spec start_children(Pleroma.Application.env()) :: :ok
  def start_children(env) do
    start_agent()

    [
      Pleroma.Plugs.RateLimiter.Supervisor,
      Oban,
      Pleroma.Web.Endpoint,
      Pleroma.Gopher.Server,
      Pleroma.Web.ChatChannel.ChatChannelState,
      Pleroma.Web.FedSockets.Supervisor
    ]
    |> add_http_children(env)
    |> add_streamer(env)
    |> Enum.each(&start_dynamic_child/1)
  end

  defp start_agent do
    {:ok, pid} = DynamicSupervisor.start_child(__MODULE__, {Agent, fn -> [] end})

    Registry.register(@registry, "agent", pid)
  end

  defp find_agent do
    [{_, pid}] = Registry.lookup(@registry, "agent")
    pid
  end

  defp add_http_children(children, :test) do
    hackney_options = Pleroma.Config.get([:hackney_pools, :federation])
    hackney_pool = :hackney_pool.child_spec(:federation, hackney_options)
    [hackney_pool, Pleroma.Pool.Supervisor | children]
  end

  defp add_http_children(children, _) do
    adapter = Application.get_env(:tesla, :adapter)

    child =
      if adapter == Tesla.Adapter.Gun do
        Pleroma.Pool.Supervisor
      else
        Pleroma.Application.HackneyPoolSupervisor
      end

    [child | children]
  end

  defp add_streamer(children, env) when env in [:test, :benchmark], do: children
  defp add_streamer(children, _), do: [Pleroma.Web.StreamerRegistry | children]

  defp start_dynamic_child(child) do
    with {:ok, pid} <- DynamicSupervisor.start_child(__MODULE__, spec(child)) do
      config_path_mappings()
      |> Enum.filter(fn {_key, module} -> child == module end)
      |> Enum.each(fn {key, _} ->
        Registry.register(@registry, key, pid)
      end)
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

  defp config_path_mappings do
    adapter_module =
      if Application.get_env(:tesla, :adapter) == Tesla.Adapter.Gun do
        Pleroma.Pool.Supervisor
      else
        Pleroma.Application.HackneyPoolSupervisor
      end

    [
      {{:pleroma, :chat}, Pleroma.Web.ChatChannel.ChatChannelState},
      {{:pleroma, Oban}, Oban},
      {{:pleroma, :rate_limit}, Pleroma.Plugs.RateLimiter.Supervisor},
      {{:pleroma, :streamer}, Pleroma.Web.Streamer.registry()},
      {{:pleroma, :pools}, Pleroma.Pool.Supervisor},
      {{:pleroma, :connections_pool}, Pleroma.Pool.Supervisor},
      {{:pleroma, :hackney_pools}, Pleroma.Application.HackneyPoolSupervisor},
      {{:pleroma, Pleroma.Captcha, [:seconds_valid]}, Pleroma.Web.Endpoint},
      {{:pleroma, Pleroma.Upload, [:proxy_remote]}, adapter_module},
      {{:pleroma, :instance, [:upload_limit]}, Pleroma.Web.Endpoint},
      {{:pleroma, :gopher, [:enabled]}, Pleroma.Gopher.Server},
      {{:pleroma, :fed_sockets, [:enabled]}, Pleroma.Web.Endpoint}
    ]
  end

  @spec save_need_reboot_paths([Pleroma.ConfigDB.t()]) :: :ok
  def save_need_reboot_paths([]), do: :ok

  def save_need_reboot_paths(configs) do
    configs
    |> Enum.map(&find_path(&1.group, &1.key, &1.value))
    |> Enum.filter(& &1)
    |> save_paths()
  end

  defp find_path(group, key, value) do
    with {path, _} <-
           Enum.find(config_path_mappings(), fn
             {{g, k}, _} ->
               g == group and k == key

             {{g, k, subkeys}, _} ->
               Keyword.keyword?(value) and g == group and k == key and
                 Enum.any?(Keyword.keys(value), &(&1 in subkeys))
           end) do
      path
    end
  end

  defp save_paths([]), do: :ok

  defp save_paths(paths), do: Agent.update(find_agent(), &Enum.uniq(&1 ++ paths))

  @spec need_reboot?() :: boolean()
  def need_reboot?, do: Agent.get(find_agent(), & &1) != []

  @spec restart_children() :: :ok
  def restart_children do
    find_agent()
    |> Agent.get_and_update(&{&1, []})
    |> Enum.each(&restart_child/1)
  end

  defp restart_child(path) do
    [{_, pid}] = Registry.lookup(@registry, path)

    # main module can have multiple keys
    # first we search for main module
    with {_, main_module} <- Enum.find(config_path_mappings(), fn {key, _} -> key == path end) do
      DynamicSupervisor.terminate_child(__MODULE__, pid)
      # then we search for keys, which depends on this main module
      config_path_mappings()
      |> Enum.filter(fn {_, module} -> main_module == module end)
      |> Enum.each(fn {key, _} ->
        Registry.unregister(@registry, key)
      end)

      start_dynamic_child(main_module)
    end
  end
end
