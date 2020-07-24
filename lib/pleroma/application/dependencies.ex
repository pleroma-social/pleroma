# # Pleroma: A lightweight social networking server
# # Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# # SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.Dependencies do
  alias Pleroma.Application.GunSupervisor
  alias Pleroma.Application.HackneySupervisor
  alias Pleroma.Config
  alias Pleroma.Web.Endpoint

  require Cachex.Spec

  @type config_path() :: {atom(), atom()} | {atom(), atom(), [atom()]}
  @type relation() :: {config_path(), module()}

  @spec static(Pleroma.Application.env()) :: [:supervisor.child_spec() | module()]
  def static(env) do
    [
      Pleroma.Emoji,
      Pleroma.Stats,
      Pleroma.JobQueueMonitor,
      %{
        id: :web_push_init,
        start: {Task, :start_link, [&Pleroma.Web.Push.init/0]},
        restart: :temporary
      }
    ]
    |> add_cachex_children()
    |> maybe_add_init_internal_fetch_actor_task(env)
    |> maybe_add(:sockets, env)
  end

  @spec dynamic(Pleroma.Application.env()) :: [:supervisor.child_spec() | module()]
  def dynamic(env) do
    [
      Pleroma.Plugs.RateLimiter.Supervisor,
      Oban,
      Endpoint,
      Pleroma.Gopher.Server,
      Pleroma.Web.ChatChannel.ChatChannelState
    ]
    |> add_http_children(env)
    |> maybe_add(:streamer, env)
  end

  @spec cachex_spec({String.t(), keyword()}) :: :supervisor.child_spec()
  def cachex_spec({type, opts}) do
    %{
      id: String.to_atom("cachex_" <> type),
      start: {Cachex, :start_link, [String.to_atom(type <> "_cache"), opts]},
      type: :worker
    }
  end

  defp add_cachex_children(children) do
    cachex_children =
      [
        {"used_captcha", ttl_interval: seconds_valid_interval()},
        {"user", default_ttl: 25_000, ttl_interval: 1000, limit: 2500},
        {"object", default_ttl: 25_000, ttl_interval: 1000, limit: 2500},
        {"rich_media", default_ttl: :timer.minutes(120), limit: 5000},
        {"scrubber", limit: 2500},
        {"idempotency", expiration: cachex_expiration(6 * 60 * 60, 60), limit: 2500},
        {"web_resp", limit: 2500},
        {"emoji_packs", expiration: cachex_expiration(5 * 60, 60), limit: 10},
        {"failed_proxy_url", limit: 2500},
        {"banned_urls", default_ttl: :timer.hours(24 * 30), limit: 5_000}
      ]
      |> Enum.map(&cachex_spec/1)

    children ++ cachex_children
  end

  defp cachex_expiration(default, interval) do
    Cachex.Spec.expiration(default: :timer.seconds(default), interval: :timer.seconds(interval))
  end

  defp seconds_valid_interval do
    [Pleroma.Captcha, :seconds_valid]
    |> Config.get!()
    |> :timer.seconds()
  end

  defp maybe_add_init_internal_fetch_actor_task(children, :test), do: children

  defp maybe_add_init_internal_fetch_actor_task(children, _) do
    children ++
      [
        %{
          id: :internal_fetch_init,
          start: {Task, :start_link, [&Pleroma.Web.ActivityPub.InternalFetchActor.init/0]},
          restart: :temporary
        }
      ]
  end

  defp maybe_add(children, _, env) when env in [:test, :benchmark], do: children
  defp maybe_add(children, :sockets, _), do: [Pleroma.Web.FedSockets.Supervisor | children]
  defp maybe_add(children, :streamer, _), do: [Pleroma.Web.Streamer.registry() | children]

  defp add_http_children(children, :test) do
    [HackneySupervisor, GunSupervisor | children]
  end

  defp add_http_children(children, _), do: [adapter_module() | children]

  defp adapter_module do
    if Application.get_env(:tesla, :adapter) == Tesla.Adapter.Gun do
      GunSupervisor
    else
      HackneySupervisor
    end
  end

  @spec save_dynamic_children_config_relations() :: :ok
  def save_dynamic_children_config_relations do
    relations = [
      {{:pleroma, :chat}, Pleroma.Web.ChatChannel.ChatChannelState},
      {{:pleroma, Oban}, Oban},
      {{:pleroma, :rate_limit}, Pleroma.Plugs.RateLimiter.Supervisor},
      {{:pleroma, :streamer}, Pleroma.Web.Streamer.registry()},
      {{:pleroma, :pools}, GunSupervisor},
      {{:pleroma, :connections_pool}, GunSupervisor},
      {{:pleroma, :hackney_pools}, HackneySupervisor},
      {{:pleroma, :gopher}, Pleroma.Gopher.Server},
      {{:pleroma, Pleroma.Captcha, [:seconds_valid]}, Endpoint},
      {{:pleroma, Pleroma.Upload, [:proxy_remote]}, adapter_module()},
      {{:pleroma, :instance, [:upload_limit]}, Endpoint},
      {{:pleroma, :fed_sockets, [:enabled]}, Endpoint}
    ]

    Config.put(:config_relations, relations)
  end

  @spec config_relations() :: [relation()]
  def config_relations, do: Config.get(:config_relations)

  @spec find_relation(config_path()) :: relation() | {:error, :relation_not_found}
  def find_relation(path) do
    with nil <- Enum.find(config_relations(), fn {key, _} -> key == path end) do
      {:error, :relation_not_found}
    end
  end

  @spec find_relation(atom(), atom(), any()) :: relation() | nil
  def find_relation(group, key, value) do
    Enum.find(config_relations(), fn
      {{g, k}, _} ->
        g == group and k == key

      {{g, k, subkeys}, _} ->
        Keyword.keyword?(value) and g == group and k == key and
          Enum.any?(Keyword.keys(value), &(&1 in subkeys))
    end)
  end

  @spec find_relations(module()) :: [relation()] | {:error, :relations_not_found}
  def find_relations(module) do
    with [] <- Enum.filter(config_relations(), fn {_, m} -> m == module end) do
      {:error, :relations_not_found}
    end
  end
end
