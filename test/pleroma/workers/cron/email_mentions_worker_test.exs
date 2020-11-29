# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.Cron.EmailMentionsWorkerTest do
  use Pleroma.DataCase
  use Oban.Testing, repo: Pleroma.Repo

  import Pleroma.Factory
  import Swoosh.TestAssertions

  alias Pleroma.Workers.Cron.EmailMentionsWorker

  setup do
    clear_config(EmailMentionsWorker, enabled: true, timeframe: 1)
    inserted_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -61)

    n1 = insert(:notification, seen: true, type: "mention", inserted_at: inserted_at)
    n2 = insert(:notification, type: "follow", inserted_at: inserted_at)
    n3 = insert(:notification, type: "mention")
    mention = insert(:notification, type: "mention", inserted_at: inserted_at)
    chat_mention = insert(:notification, type: "pleroma:chat_mention", inserted_at: inserted_at)

    n4 =
      insert(:notification,
        type: "mention",
        notified_at: NaiveDateTime.utc_now(),
        inserted_at: inserted_at
      )

    [
      mention: mention,
      chat_mention: chat_mention,
      other_user_ids: [n1.user_id, n2.user_id, n3.user_id, n4.user_id]
    ]
  end

  test "creates jobs for users", %{
    mention: mention,
    chat_mention: chat_mention,
    other_user_ids: ids
  } do
    assert EmailMentionsWorker.perform(%{}) == :ok

    assert_enqueued(
      worker: EmailMentionsWorker,
      args: %{op: "email_mentions", user_id: mention.user_id}
    )

    assert_enqueued(
      worker: EmailMentionsWorker,
      args: %{op: "email_mentions", user_id: chat_mention.user_id}
    )

    Enum.each(ids, fn id ->
      refute_enqueued(worker: EmailMentionsWorker, args: %{op: "email_mentions", user_id: id})
    end)

    assert Repo.aggregate(Oban.Job, :count, :id) == 2

    EmailMentionsWorker.perform(%{})

    # no duplicates
    assert Repo.aggregate(Oban.Job, :count, :id) == 2
  end

  test "doesn't create jobs for users without emails", %{mention: mention} do
    %{user: user} = Repo.preload(mention, :user)

    user
    |> Ecto.Changeset.change(email: nil)
    |> Repo.update()

    assert EmailMentionsWorker.perform(%{}) == :ok

    refute_enqueued(
      worker: EmailMentionsWorker,
      args: %{op: "email_mentions", user_id: mention.user_id}
    )
  end

  test "sends emails", %{mention: mention, chat_mention: chat_mention} do
    assert EmailMentionsWorker.perform(%{}) == :ok

    mention = Repo.preload(mention, :user)

    assert EmailMentionsWorker.perform(%Oban.Job{
             args: %{"op" => "email_mentions", "user_id" => mention.user_id}
           }) == :ok

    assert_email_sent(
      to: {mention.user.name, mention.user.email},
      html_body: ~r/here is what you've missed!/i
    )

    chat_mention = Repo.preload(chat_mention, :user)

    assert EmailMentionsWorker.perform(%Oban.Job{
             args: %{"op" => "email_mentions", "user_id" => chat_mention.user_id}
           }) == :ok

    assert_email_sent(
      to: {chat_mention.user.name, chat_mention.user.email},
      html_body: ~r/here is what you've missed!/i
    )
  end
end
