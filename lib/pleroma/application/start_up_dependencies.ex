# # Pleroma: A lightweight social networking server
# # Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# # SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.StartUpDependencies do
  alias Pleroma.Config
  alias Pleroma.Web.Endpoint

  require Cachex.Spec
  require Logger

  @type config_path() :: {atom(), atom()} | {atom(), atom(), [atom()]}
  @type relation() :: {config_path(), module()}

  @spec start_all(Pleroma.Application.env()) ::
          :ok | {:error, {:already_started, pid()} | :max_children | term()}
  def start_all(env) do
    with :ok <- start_common_deps(env),
         :ok <- start_config_dependent_deps(env) do
      :ok
    end
  end

  @spec adapter_module() :: module()
  def adapter_module do
    if Application.get_env(:tesla, :adapter) == Tesla.Adapter.Gun do
      Pleroma.Gun.GunSupervisor
    else
      Pleroma.HTTP.HackneySupervisor
    end
  end

  def spec(Oban), do: {Oban, Config.get(Oban)}

  def spec(Pleroma.Web.StreamerRegistry) do
    {Registry,
     [
       name: Pleroma.Web.Streamer.registry(),
       keys: :duplicate,
       partitions: System.schedulers_online()
     ]}
  end

  def spec(child), do: child

  @spec cachex_spec({String.t(), keyword()}) :: :supervisor.child_spec()
  def cachex_spec({type, opts}) do
    %{
      id: String.to_atom("cachex_" <> type),
      start: {Cachex, :start_link, [String.to_atom(type <> "_cache"), opts]},
      type: :worker
    }
  end

  defp start_common_deps(env) do
    fun = fn child ->
      DynamicSupervisor.start_child(Pleroma.Application.dynamic_supervisor(), spec(child))
    end

    [
      Pleroma.Emoji,
      Pleroma.Stats,
      Pleroma.JobQueueMonitor,
      {Majic.Pool, [name: Pleroma.MajicPool, pool_size: Config.get([:majic_pool, :size], 2)]},
      %{
        id: :web_push_init,
        start: {Task, :start_link, [&Pleroma.Web.Push.init/0]},
        restart: :temporary
      }
    ]
    |> add_cachex_deps()
    |> maybe_add_init_internal_fetch_actor_task(env)
    |> maybe_add_pub_sub()
    |> start_while(fun)
  end

  defp start_config_dependent_deps(env) do
    fun = fn child -> Pleroma.Application.ConfigDependentDeps.start_dependency(child) end

    [
      Pleroma.Web.Plugs.RateLimiter.Supervisor,
      Oban,
      Endpoint,
      Pleroma.Gopher.Server
    ]
    |> add_http_children(env)
    |> maybe_add(:streamer, env)
    |> maybe_add_chat_child()
    |> start_while(fun)
  end

  defp start_while(deps, fun) do
    Enum.reduce_while(deps, :ok, fn child, acc ->
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

  @spec cachex_deps() :: [tuple()]
  def cachex_deps do
    captcha_clean_up_interval =
      [Pleroma.Captcha, :seconds_valid]
      |> Config.get!()
      |> :timer.seconds()

    [
      {"used_captcha", expiration: Cachex.Spec.expiration(interval: captcha_clean_up_interval)},
      {"user", expiration: cachex_expiration(25_000, 1000), limit: 2500},
      {"object", expiration: cachex_expiration(25_000, 1000), limit: 2500},
      {"rich_media",
       expiration: Cachex.Spec.expiration(default: :timer.minutes(120)), limit: 5000},
      {"scrubber", limit: 2500},
      {"idempotency", expiration: cachex_expiration(21_600, 60), limit: 2500},
      {"web_resp", limit: 2500},
      {"emoji_packs", expiration: cachex_expiration(300, 60), limit: 10},
      {"failed_proxy_url", limit: 2500},
      {"banned_urls",
       expiration: Cachex.Spec.expiration(default: :timer.hours(24 * 30)), limit: 5_000},
      {"chat_message_id_idempotency_key",
       expiration: cachex_expiration(:timer.minutes(2), :timer.seconds(60)), limit: 500_000}
    ]
  end

  defp add_cachex_deps(application_deps) do
    cachex_deps()
    |> Enum.reduce(application_deps, fn cachex_init_args, acc ->
      [cachex_spec(cachex_init_args) | acc]
    end)
  end

  defp cachex_expiration(default, interval) do
    Cachex.Spec.expiration(default: :timer.seconds(default), interval: :timer.seconds(interval))
  end

  defp maybe_add_init_internal_fetch_actor_task(children, :test), do: children

  defp maybe_add_init_internal_fetch_actor_task(children, _) do
    [
      %{
        id: :internal_fetch_init,
        start: {Task, :start_link, [&Pleroma.Web.ActivityPub.InternalFetchActor.init/0]},
        restart: :temporary
      }
      | children
    ]
  end

  defp maybe_add(children, _, env) when env in [:test, :benchmark], do: children
  defp maybe_add(children, :streamer, _), do: [Pleroma.Web.Streamer.registry() | children]

  defp add_http_children(children, :test) do
    [Pleroma.HTTP.HackneySupervisor, Pleroma.Gun.GunSupervisor | children]
  end

  defp add_http_children(children, _), do: [adapter_module() | children]

  defp maybe_add_chat_child(children) do
    if Config.get([:chat, :enabled]) do
      [Pleroma.Web.ChatChannel.ChatChannelState | children]
    else
      children
    end
  end

  defp maybe_add_pub_sub(children) do
    if Config.get([:chat, :enabled]) do
      [{Phoenix.PubSub, [name: Pleroma.PubSub, adapter: Phoenix.PubSub.PG2]} | children]
    else
      children
    end
  end
end
