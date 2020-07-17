# # Pleroma: A lightweight social networking server
# # Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# # SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.DynamicSupervisor do
  use DynamicSupervisor

  require Logger

  @type child() ::
          Supervisor.child_spec()
          | {module(), term()}
          | module()

  def start_link(_), do: DynamicSupervisor.start_link(__MODULE__, :no_arg, name: __MODULE__)

  @impl true
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec start_child(child()) :: DynamicSupervisor.on_start_child()
  def start_child(child), do: DynamicSupervisor.start_child(__MODULE__, child)

  @spec start_children(Pleroma.Application.env()) :: :ok
  def start_children(env) do
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

  defp add_http_children(children, :test) do
    [Pleroma.Application.HackneySupervisor, Pleroma.Application.GunSupervisor | children]
  end

  defp add_http_children(children, _) do
    adapter = Application.get_env(:tesla, :adapter)

    child =
      if adapter == Tesla.Adapter.Gun do
        Pleroma.Application.GunSupervisor
      else
        Pleroma.Application.HackneySupervisor
      end

    [child | children]
  end

  defp add_streamer(children, env) when env in [:test, :benchmark], do: children
  defp add_streamer(children, _), do: [Pleroma.Web.StreamerRegistry | children]

  defp start_dynamic_child(child) do
    with {:ok, pid} <- dynamic_child(child),
         mappings <- find_mappings(child) do
      Enum.each(mappings, fn {key, _} ->
        Pleroma.Application.Agent.put_pid(key, pid)
      end)
    else
      :ignore ->
        # consider this behavior is normal
        Logger.info("#{inspect(child)} is ignored.")

      error ->
        Logger.warn(inspect(error))
    end
  end

  defp dynamic_child(child) do
    with {:error, _} = error <- DynamicSupervisor.start_child(__MODULE__, spec(child)) do
      error
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
        Pleroma.Application.GunSupervisor
      else
        Pleroma.Application.HackneySupervisor
      end

    [
      {{:pleroma, :chat}, Pleroma.Web.ChatChannel.ChatChannelState},
      {{:pleroma, Oban}, Oban},
      {{:pleroma, :rate_limit}, Pleroma.Plugs.RateLimiter.Supervisor},
      {{:pleroma, :streamer}, Pleroma.Web.Streamer.registry()},
      {{:pleroma, :pools}, Pleroma.Application.GunSupervisor},
      {{:pleroma, :connections_pool}, Pleroma.Application.GunSupervisor},
      {{:pleroma, :hackney_pools}, Pleroma.Application.HackneySupervisor},
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

  defp save_paths(paths), do: Pleroma.Application.Agent.put_paths(paths)

  @spec need_reboot?() :: boolean()
  def need_reboot?, do: Pleroma.Application.Agent.paths() != []

  @spec restart_children() :: :ok
  def restart_children do
    Pleroma.Application.Agent.get_and_reset_paths()
    |> Enum.each(&restart_child/1)
  end

  defp restart_child(path) do
    pid = Pleroma.Application.Agent.pid(path)

    # main module can have multiple keys
    # first we search for main module
    with {_, module} <- find_mapping(path),
         :ok <- terminate(pid),
         # then we search for mappings, which depends on this main module
         mappings <- find_mappings(module) do
      Enum.each(mappings, fn {key, _} ->
        Pleroma.Application.Agent.delete_pid(key)
      end)

      start_dynamic_child(module)
    else
      error ->
        Logger.warn(inspect(error))
    end
  end

  defp find_mapping(path) do
    with nil <- Enum.find(config_path_mappings(), fn {key, _} -> key == path end) do
      {:error, :mapping_not_found}
    end
  end

  defp find_mappings(module) do
    with [] <- Enum.filter(config_path_mappings(), fn {_, m} -> m == module end) do
      {:error, :empty_mappings}
    end
  end

  defp terminate(pid) do
    with {:error, :not_found} = error <- DynamicSupervisor.terminate_child(__MODULE__, pid) do
      error
    end
  end
end
