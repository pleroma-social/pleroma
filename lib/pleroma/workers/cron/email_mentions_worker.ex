# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.Cron.EmailMentionsWorker do
  use Pleroma.Workers.WorkerHelper, queue: "email_mentions"

  @impl true
  def perform(%Job{args: %{"op" => "email_mentions", "user_id" => id}}) do
    user = Pleroma.User.get_cached_by_id(id)

    timeframe =
      Pleroma.Config.get([__MODULE__, :timeframe], 30)
      |> :timer.minutes()

    max_inserted_at =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-timeframe, :millisecond)
      |> NaiveDateTime.truncate(:second)

    mentions = Pleroma.Notification.for_user_unread_mentions(user, max_inserted_at)

    if mentions != [] do
      user
      |> Pleroma.Emails.UserEmail.mentions_notification_email(mentions)
      |> Pleroma.Emails.Mailer.deliver()
      |> case do
        {:ok, _} ->
          Enum.map(mentions, & &1.id)

        _ ->
          []
      end
      |> Pleroma.Notification.update_notified_at()
    end

    :ok
  end

  @impl true
  def perform(_) do
    config = Pleroma.Config.get(__MODULE__, [])

    if Keyword.get(config, :enabled, false) do
      timeframe = Keyword.get(config, :timeframe, 30)
      period = timeframe * 60

      max_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-:timer.minutes(timeframe), :millisecond)
        |> NaiveDateTime.truncate(:second)

      Pleroma.Notification.users_ids_with_unread_mentions(max_at)
      |> Enum.each(&insert_job(&1, unique: [period: period]))
    end

    :ok
  end

  defp insert_job(user_id, args) do
    Pleroma.Workers.Cron.EmailMentionsWorker.enqueue(
      "email_mentions",
      %{"user_id" => user_id},
      args
    )
  end
end
