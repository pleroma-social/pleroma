# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Frontend.StaticController do
  use Pleroma.Web, :controller

  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Visibility
  alias Pleroma.Web.Metadata

  plug(:put_layout, :static_fe)

  plug(Pleroma.Plugs.EnsureAuthenticatedPlug,
    unless_func: &Pleroma.Web.FederatingPlug.federating?/1
  )

  @page_keys ["max_id", "min_id", "limit", "since_id", "order"]

  def object(conn, %{"uuid" => _uuid}) do
    url = url(conn) <> conn.request_path

    case Activity.get_create_by_object_ap_id_with_object(url) do
      %Activity{} = activity ->
        to = o_status_path(Pleroma.Web.Endpoint, :notice, activity)
        redirect(conn, to: to)

      _ ->
        not_found(conn, "Post not found.")
    end
  end

  def notice(conn, %{"id" => notice_id}) do
    with %Activity{local: true} = activity <-
           Activity.get_by_id_with_object(notice_id),
         true <- Visibility.is_public?(activity.object),
         %User{} = user <- User.get_by_ap_id(activity.object.data["actor"]) do
      meta = Metadata.build_tags(%{activity_id: notice_id, object: activity.object, user: user})

      timeline =
        activity.object.data["context"]
        |> ActivityPub.fetch_activities_for_context(%{})
        |> Enum.reverse()
        |> Enum.map(&represent(&1, &1.object.id == activity.object.id))

      render(conn, "conversation.html", %{activities: timeline, meta: meta})
    else
      %Activity{object: %Object{data: data}} ->
        conn
        |> put_status(:found)
        |> redirect(external: data["url"] || data["external_url"] || data["id"])

      _ ->
        not_found(conn, "Post not found.")
    end
  end

  def feed_redirect(conn, %{"nickname" => username_or_id} = params) do
    case User.get_cached_by_nickname_or_id(username_or_id) do
      %User{} = user ->
        meta = Metadata.build_tags(%{user: user})

        params =
          params
          |> Map.take(@page_keys)
          |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

        timeline =
          user
          |> ActivityPub.fetch_user_activities(nil, params)
          |> Enum.map(&represent/1)

        prev_page_id =
          (params["min_id"] || params["max_id"]) &&
            List.first(timeline) && List.first(timeline).id

        next_page_id = List.last(timeline) && List.last(timeline).id

        render(conn, "profile.html", %{
          user: User.sanitize_html(user),
          timeline: timeline,
          prev_page_id: prev_page_id,
          next_page_id: next_page_id,
          meta: meta
        })

      _ ->
        not_found(conn, "User not found.")
    end
  end

  def activity(conn, %{"uuid" => _uuid}) do
    url = url(conn) <> conn.request_path

    case Activity.get_by_ap_id(url) do
      %Activity{} = activity ->
        to = o_status_path(Pleroma.Web.Endpoint, :notice, activity)
        redirect(conn, to: to)

      _ ->
        not_found(conn, "Post not found.")
    end
  end

  defp get_title(%Object{data: %{"name" => name}}) when is_binary(name),
    do: name

  defp get_title(%Object{data: %{"summary" => summary}}) when is_binary(summary),
    do: summary

  defp get_title(_), do: nil

  defp not_found(conn, message) do
    conn
    |> put_status(404)
    |> render("error.html", %{message: message, meta: ""})
  end

  defp get_counts(%Activity{} = activity) do
    %Object{data: data} = Object.normalize(activity)

    %{
      likes: data["like_count"] || 0,
      replies: data["repliesCount"] || 0,
      announces: data["announcement_count"] || 0
    }
  end

  defp represent(%Activity{} = activity), do: represent(activity, false)

  defp represent(%Activity{object: %Object{data: data}} = activity, selected) do
    {:ok, user} = User.get_or_fetch(activity.object.data["actor"])

    link =
      if user.local do
        o_status_url(Pleroma.Web.Endpoint, :notice, activity)
      else
        data["url"] || data["external_url"] || data["id"]
      end

    content =
      if data["content"] do
        data["content"]
        |> Pleroma.HTML.filter_tags()
        |> Pleroma.Emoji.Formatter.emojify(Map.get(data, "emoji", %{}))
      end

    %{
      user: User.sanitize_html(user),
      title: get_title(activity.object),
      content: content,
      attachment: data["attachment"],
      link: link,
      published: data["published"],
      sensitive: data["sensitive"],
      selected: selected,
      counts: get_counts(activity),
      id: activity.id
    }
  end
end
