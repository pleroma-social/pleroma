# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.PollExpirationNotify do
  @moduledoc false

  use Oban.Worker, queue: :poll_expiration_notify, max_attempts: 1

  def enqueue(args) do
    {scheduled_at, args} = Map.pop(args, :closed_at)

    args
    |> __MODULE__.new(scheduled_at: scheduled_at)
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"activity_id" => activity_id}}) do
    Pleroma.Web.CommonAPI.close_poll(activity_id)
    :ok
  end

  def perform(_), do: :ok
end
