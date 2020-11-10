# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.MRF.AutoSubjectPolicy do
  alias Pleroma.User

  require Pleroma.Constants

  require Logger

  @moduledoc "Apply Subject to local posts matching certain keywords."

  @behaviour Pleroma.Web.ActivityPub.MRF

  defp string_matches?(string, _) when not is_binary(string) do
    false
  end

  defp string_matches?(string, pattern) when is_binary(pattern) do
    String.contains?(string, pattern)
  end

  defp string_matches?(string, pattern) do
    String.match?(string, pattern)
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
        fn {pat, key} ->
          if string_matches?(String.downcase(object["content"]), String.downcase(pat)) do
            key
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
        "Adds subject to messages matching a keyword or [Regex](https://hexdocs.pm/elixir/Regex.html).",
      children: [
        %{
          key: :match,
          type: {:list, :tuple},
          description: """
            **Pattern**: a string or [Regex](https://hexdocs.pm/elixir/Regex.html) in the format of `~r/PATTERN/`.

            **Keyword**: a keyword to apply to the subject field.
          """
        }
      ]
    }
  end
end
