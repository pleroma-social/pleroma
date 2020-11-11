# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.MRF.AutoSubjectPolicy do
  alias Pleroma.User

  require Pleroma.Constants

  require Logger

  @moduledoc "Apply Subject to local posts matching certain keywords."

  @behaviour Pleroma.Web.ActivityPub.MRF

  defp string_matches?(content, _) when not is_binary(content) do
    false
  end

  defp string_matches?(content, keywords) when is_list(keywords) do
    wordlist = content |> String.downcase() |> String.split(" ", trim: true) |> Enum.uniq()
    Enum.any?(keywords, fn match -> String.downcase(match) in wordlist end)
  end

  defp string_matches?(content, keyword) when is_binary(keyword) do
    wordlist = content |> String.downcase() |> String.split(" ", trim: true) |> Enum.uniq()
    String.downcase(keyword) in wordlist
  end

  defp check_subject(%{"object" => %{} = object} = message) do
    if String.length(object["summary"] |> String.trim()) == 0 do
      {:ok, message}
    else
      {:error, :has_subject}
    end
  end

  defp check_match(%{"object" => %{} = object} = message) do
    auto_summary =
      Enum.map(
        Pleroma.Config.get([:mrf_auto_subject, :match]),
        fn {keyword, subject} ->
          if string_matches?(object["content"], keyword) do
            subject
          end
        end
      )
      |> Enum.filter(& &1)
      |> Enum.join(", ")

    object = Map.put(object, "summary", auto_summary)

    message = Map.put(message, "object", object)

    {:ok, message}
  end

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

  @impl true
  def describe do
    # This horror is needed to convert regex sigils to strings
    mrf_autosubject =
      Pleroma.Config.get(:mrf_autosubject, [])
      |> Enum.map(fn {key, value} ->
        {key,
         Enum.map(value, fn
           {pattern, keyword} ->
             %{
               "pattern" =>
                 if not is_binary(pattern) do
                   inspect(pattern)
                 else
                   pattern
                 end,
               "keyword" => keyword
             }

           pattern ->
             if not is_binary(pattern) do
               inspect(pattern)
             else
               pattern
             end
         end)}
      end)
      |> Enum.into(%{})

    {:ok, %{mrf_autosubject: mrf_autosubject}}
  end

  @impl true
  def config_description do
    %{
      key: :mrf_autosubject,
      related_policy: "Pleroma.Web.ActivityPub.MRF.AutoSubjectPolicy",
      label: "MRF AutoSubject",
      description:
        "Adds subject to messages matching a keyword or list of keywords.",
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
