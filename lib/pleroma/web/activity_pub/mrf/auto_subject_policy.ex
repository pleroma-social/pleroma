# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.MRF.AutoSubjectPolicy do
  @moduledoc "Apply Subject to local posts matching certain keywords."

  @behaviour Pleroma.Web.ActivityPub.MRF

  alias Pleroma.User

  require Pleroma.Constants
  require Logger

  @impl true
  def filter(%{"type" => "Create", "actor" => actor, "object" => _object} = message) do
    with {:ok, %User{local: true}} <- User.get_or_fetch_by_ap_id(actor),
         {:ok, message} <- check_subject(message),
         {:ok, message} <- check_match(message) do
      {:ok, message}
    else
      {:ok, %User{local: false}} ->
        {:ok, message}

      {:error, :has_subject} ->
        {:ok, message}

      {:error, _} ->
        {:reject, "[AutoSubjectPolicy] Failed to get or fetch user by ap_id"}

      e ->
        {:reject, "[AutoSubjectPolicy] Unhandled error #{inspect(e)}"}
    end
  end

  @impl true
  def filter(message), do: {:ok, message}

  defp check_subject(%{"object" => %{"summary" => subject}} = message) do
    subject = String.trim(subject)

    if String.length(subject) == 0 do
      {:ok, message}
    else
      {:error, :has_subject}
    end
  end

  defp check_subject(message), do: {:ok, message}

  defp string_matches?(content, pattern) when is_binary(content) do
    String.contains?(content, pattern)
  end

  defp check_match(%{"object" => %{} = object} = message) do
    match_settings = Pleroma.Config.get([:mrf_auto_subject, :match])

    auto_summary =
      Enum.reduce(match_settings, [], fn {keywords, subject}, acc ->
        if string_matches?(object["content"], keywords) do
          [subject | acc]
        else
          acc
        end
      end)
      |> Enum.join(", ")

    message = put_in(message["object"]["summary"], auto_summary)

    {:ok, message}
  end

  @impl true
  def describe do
    mrf_autosubject =
      :mrf_auto_subject
      |> Pleroma.Config.get()
      |> Enum.into(%{})

    {:ok, %{mrf_auto_subject: mrf_autosubject}}
  end

  @impl true
  def config_description do
    %{
      key: :mrf_auto_subject,
      related_policy: "Pleroma.Web.ActivityPub.MRF.AutoSubjectPolicy",
      label: "MRF AutoSubject",
      description:
        "Adds subject to messages matching a keyword or list of keywords if no subject is defined.",
      children: [
        %{
          key: :match,
          type: {:list, :tuple},
          description: """
            **Keyword**: a string or list of keywords. E.g., ["cat", "dog"] to match on both "cat" and "dog".

            **Subject**: a string to insert into the subject field.

            Note: the keyword matching is case-insensitive and matches only the whole word.
          """
        }
      ]
    }
  end
end
