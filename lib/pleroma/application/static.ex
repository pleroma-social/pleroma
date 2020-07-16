# # Pleroma: A lightweight social networking server
# # Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# # SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.Static do
  require Cachex.Spec

  @spec start_children(Pleroma.Application.env()) :: :ok
  def start_children(env) do
    children =
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
      |> add_init_internal_fetch_actor_task(env)

    Enum.each(children, &Pleroma.Application.DynamicSupervisor.start_child/1)
  end

  @spec build_cachex({String.t(), keyword()}) :: map()
  def build_cachex({type, opts}) do
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
      |> Enum.map(&build_cachex/1)

    children ++ cachex_children
  end

  defp cachex_expiration(default, interval) do
    Cachex.Spec.expiration(default: :timer.seconds(default), interval: :timer.seconds(interval))
  end

  defp seconds_valid_interval do
    [Pleroma.Captcha, :seconds_valid]
    |> Pleroma.Config.get!()
    |> :timer.seconds()
  end

  defp add_init_internal_fetch_actor_task(children, :test), do: children

  defp add_init_internal_fetch_actor_task(children, _) do
    children ++
      [
        %{
          id: :internal_fetch_init,
          start: {Task, :start_link, [&Pleroma.Web.ActivityPub.InternalFetchActor.init/0]},
          restart: :temporary
        }
      ]
  end
end
