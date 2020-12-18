# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Transmogrifier do
  @moduledoc """
  A module to handle coding from internal to wire ActivityPub and back.
  """
  alias Pleroma.Activity
  alias Pleroma.EctoType.ActivityPub.ObjectValidators
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Builder
  alias Pleroma.Web.ActivityPub.ObjectValidator
  alias Pleroma.Web.ActivityPub.Pipeline
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.ActivityPub.Visibility
  alias Pleroma.Web.Federator
  alias Pleroma.Workers.TransmogrifierWorker

  import Ecto.Query

  require Logger
  require Pleroma.Constants

  # if as:Public is addressed, then make sure the followers collection is also addressed
  # so that the activities will be delivered to local users.
  def fix_implicit_addressing(%{"to" => to, "cc" => cc} = object, followers_collection) do
    recipients = to ++ cc

    if followers_collection not in recipients do
      cond do
        Pleroma.Constants.as_public() in cc ->
          to = to ++ [followers_collection]
          Map.put(object, "to", to)

        Pleroma.Constants.as_public() in to ->
          cc = cc ++ [followers_collection]
          Map.put(object, "cc", cc)

        true ->
          object
      end
    else
      object
    end
  end

  defp fix_in_reply_to(%{"inReplyTo" => in_reply_to} = object, options)
       when not is_nil(in_reply_to) do
    in_reply_to_id = prepare_in_reply_to(in_reply_to)
    depth = (options[:depth] || 0) + 1

    if Federator.allowed_thread_distance?(depth) do
      with {:ok, replied_object} <- get_obj_helper(in_reply_to_id, options),
           %Activity{} <- Activity.get_create_by_object_ap_id(replied_object.data["id"]) do
        object
        |> Map.put("inReplyTo", replied_object.data["id"])
        |> Map.put("context", replied_object.data["context"] || object["conversation"])
        |> Map.drop(["conversation", "inReplyToAtomUri"])
      else
        e ->
          Logger.warn("Couldn't fetch #{inspect(in_reply_to_id)}, error: #{inspect(e)}")
          object
      end
    else
      object
    end
  end

  defp fix_in_reply_to(object, _options), do: object

  defp prepare_in_reply_to(in_reply_to) do
    cond do
      is_bitstring(in_reply_to) ->
        in_reply_to

      is_map(in_reply_to) && is_bitstring(in_reply_to["id"]) ->
        in_reply_to["id"]

      is_list(in_reply_to) && is_bitstring(Enum.at(in_reply_to, 0)) ->
        Enum.at(in_reply_to, 0)

      true ->
        ""
    end
  end

  def fix_emoji(%{"tag" => tags} = object) when is_list(tags) do
    emoji =
      tags
      |> Enum.filter(fn data -> is_map(data) and data["type"] == "Emoji" and data["icon"] end)
      |> Enum.reduce(%{}, fn data, mapping ->
        name = String.trim(data["name"], ":")

        Map.put(mapping, name, data["icon"]["url"])
      end)

    Map.put(object, "emoji", emoji)
  end

  def fix_emoji(%{"tag" => %{"type" => "Emoji"} = tag} = object) do
    name = String.trim(tag["name"], ":")
    emoji = %{name => tag["icon"]["url"]}

    Map.put(object, "emoji", emoji)
  end

  def fix_emoji(object), do: object

  def fix_tag(%{"tag" => tag} = object) when is_list(tag) do
    hashtags =
      tag
      |> Enum.filter(fn data -> data["type"] == "Hashtag" and data["name"] end)
      |> Enum.map(fn
        %{"name" => "#" <> hashtag} -> String.downcase(hashtag)
        %{"name" => hashtag} -> String.downcase(hashtag)
      end)

    Map.put(object, "hashtags", hashtags)
  end

  def fix_tag(%{"tag" => %{} = tag} = object) do
    object
    |> Map.put("tag", [tag])
    |> fix_tag
  end

  def fix_tag(object), do: object

  # content map usually only has one language so this will do for now.
  def fix_content_map(%{"contentMap" => content_map} = object) do
    content_groups = Map.to_list(content_map)
    {_, content} = Enum.at(content_groups, 0)

    Map.put(object, "content", content)
  end

  def fix_content_map(object), do: object

  defp fix_type(%{"type" => "Note", "inReplyTo" => reply_id, "name" => _} = object, options)
       when is_binary(reply_id) do
    with %Object{data: %{"type" => "Question"}} <- Object.normalize(reply_id, true, options) do
      Map.put(object, "type", "Answer")
    else
      _ -> object
    end
  end

  defp fix_type(object, _options), do: object

  # Reduce the object list to find the reported user.
  defp get_reported(objects) do
    Enum.reduce_while(objects, nil, fn ap_id, _ ->
      with %User{} = user <- User.get_cached_by_ap_id(ap_id) do
        {:halt, user}
      else
        _ -> {:cont, nil}
      end
    end)
  end

  def handle_incoming(data, options \\ [])

  # Flag objects are placed ahead of the ID check because Mastodon 2.8 and earlier send them
  # with nil ID.
  def handle_incoming(%{"type" => "Flag", "object" => objects, "actor" => actor} = data, _options) do
    with context <- data["context"] || Utils.generate_context_id(),
         content <- data["content"] || "",
         %User{} = actor <- User.get_cached_by_ap_id(actor),
         # Reduce the object list to find the reported user.
         %User{} = account <- get_reported(objects),
         # Remove the reported user from the object list.
         statuses <- Enum.filter(objects, fn ap_id -> ap_id != account.ap_id end) do
      %{
        actor: actor,
        context: context,
        account: account,
        statuses: statuses,
        content: content,
        additional: %{"cc" => [account.ap_id]}
      }
      |> ActivityPub.flag()
    end
  end

  # disallow objects with bogus IDs
  def handle_incoming(%{"id" => nil}, _options), do: :error
  def handle_incoming(%{"id" => ""}, _options), do: :error
  # length of https:// = 8, should validate better, but good enough for now.
  def handle_incoming(%{"id" => id}, _options) when is_binary(id) and byte_size(id) < 8,
    do: :error

  @misskey_reactions %{
    "like" => "👍",
    "love" => "❤️",
    "laugh" => "😆",
    "hmm" => "🤔",
    "surprise" => "😮",
    "congrats" => "🎉",
    "angry" => "💢",
    "confused" => "😥",
    "rip" => "😇",
    "pudding" => "🍮",
    "star" => "⭐"
  }

  @doc "Rewrite misskey likes into EmojiReacts"
  def handle_incoming(
        %{
          "type" => "Like",
          "_misskey_reaction" => reaction
        } = data,
        options
      ) do
    data
    |> Map.put("type", "EmojiReact")
    |> Map.put("content", @misskey_reactions[reaction] || reaction)
    |> handle_incoming(options)
  end

  def handle_incoming(
        %{"type" => "Create", "object" => %{"type" => objtype, "id" => obj_id}} = data,
        options
      )
      when objtype in ~w{Question Answer ChatMessage Audio Video Event Article Note} do
    fetch_options = Keyword.put(options, :depth, (options[:depth] || 0) + 1)

    object =
      data["object"]
      |> strip_internal_fields()
      |> fix_type(fetch_options)
      |> fix_in_reply_to(fetch_options)

    data = Map.put(data, "object", object)
    options = Keyword.put(options, :local, false)

    with {:ok, %User{}} <- ObjectValidator.fetch_actor(data),
         nil <- Activity.get_create_by_object_ap_id(obj_id),
         {:ok, activity, _} <- Pipeline.common_pipeline(data, options) do
      {:ok, activity}
    else
      %Activity{} = activity -> {:ok, activity}
      e -> e
    end
  end

  def handle_incoming(%{"type" => type} = data, _options)
      when type in ~w{Like EmojiReact Announce} do
    with :ok <- ObjectValidator.fetch_actor_and_object(data),
         {:ok, activity, _meta} <-
           Pipeline.common_pipeline(data, local: false) do
      {:ok, activity}
    else
      e -> {:error, e}
    end
  end

  def handle_incoming(
        %{"type" => type} = data,
        _options
      )
      when type in ~w{Update Block Follow Accept Reject} do
    with {:ok, %User{}} <- ObjectValidator.fetch_actor(data),
         {:ok, activity, _} <-
           Pipeline.common_pipeline(data, local: false) do
      {:ok, activity}
    end
  end

  def handle_incoming(
        %{"type" => "Delete"} = data,
        _options
      ) do
    with {:ok, activity, _} <-
           Pipeline.common_pipeline(data, local: false) do
      {:ok, activity}
    else
      {:error, {:validate_object, _}} = e ->
        # Check if we have a create activity for this
        with {:ok, object_id} <- ObjectValidators.ObjectID.cast(data["object"]),
             %Activity{data: %{"actor" => actor}} <-
               Activity.create_by_object_ap_id(object_id) |> Repo.one(),
             # We have one, insert a tombstone and retry
             {:ok, tombstone_data, _} <- Builder.tombstone(actor, object_id),
             {:ok, _tombstone} <- Object.create(tombstone_data) do
          handle_incoming(data)
        else
          _ -> e
        end
    end
  end

  def handle_incoming(
        %{"type" => "Undo", "object" => %{"type" => objtype, "id" => object_id}} = data,
        _options
      )
      when objtype in ~w[Like EmojiReact Announce Block Follow] do
    with {:ok, %User{}} <- ObjectValidator.fetch_actor(data),
         {_, %Activity{}} <- {:exists, Activity.get_by_ap_id(object_id)},
         {:ok, activity, _} <- Pipeline.common_pipeline(data, local: false) do
      {:ok, activity}
    else
      {:error, _} = e -> e
      e -> {:error, e}
    end
  end

  # For Undos that don't have the complete object attached, try to find it in our database.
  def handle_incoming(%{"type" => "Undo", "object" => object} = activity, options)
      when is_binary(object) do
    with %Activity{data: data} <- Activity.get_by_ap_id(object) do
      activity
      |> Map.put("object", data)
      |> handle_incoming(options)
    else
      {:error, _} = e -> e
      e -> {:error, e}
    end
  end

  def handle_incoming(
        %{
          "type" => "Move",
          "actor" => origin_actor,
          "object" => origin_actor,
          "target" => target_actor
        },
        _options
      ) do
    with %User{} = origin_user <- User.get_cached_by_ap_id(origin_actor),
         {:ok, %User{} = target_user} <- User.get_or_fetch_by_ap_id(target_actor),
         true <- origin_actor in target_user.also_known_as do
      ActivityPub.move(origin_user, target_user, false)
    else
      _e -> :error
    end
  end

  def handle_incoming(_, _), do: :error

  @spec get_obj_helper(String.t(), Keyword.t()) :: {:ok, Object.t()} | nil
  defp get_obj_helper(id, options \\ []) do
    case Object.normalize(id, true, options) do
      %Object{} = object -> {:ok, object}
      _ -> nil
    end
  end

  defp set_reply_to_uri(%{"inReplyTo" => in_reply_to} = object) when is_binary(in_reply_to) do
    with false <- String.starts_with?(in_reply_to, "http"),
         {:ok, %{data: replied_to_object}} <- get_obj_helper(in_reply_to) do
      Map.put(object, "inReplyTo", replied_to_object["external_url"] || in_reply_to)
    else
      _e -> object
    end
  end

  defp set_reply_to_uri(obj), do: obj

  # Serialized Mastodon-compatible `replies` collection containing _self-replies_.
  # Based on Mastodon's ActivityPub::NoteSerializer#replies.
  defp set_replies(obj_data) do
    replies_uris =
      with limit when limit > 0 <-
             Pleroma.Config.get([:activitypub, :note_replies_output_limit], 0),
           %Object{} = object <- Object.get_cached_by_ap_id(obj_data["id"]) do
        object
        |> Object.self_replies()
        |> select([o], fragment("?->>'id'", o.data))
        |> limit(^limit)
        |> Repo.all()
      else
        _ -> []
      end

    set_replies(obj_data, replies_uris)
  end

  defp set_replies(obj, []) do
    obj
  end

  defp set_replies(obj, replies_uris) do
    replies_collection = %{
      "type" => "Collection",
      "items" => replies_uris
    }

    Map.merge(obj, %{"replies" => replies_collection})
  end

  # Prepares the object of an outgoing create activity.
  def prepare_object(object) do
    object
    |> set_sensitive
    |> add_hashtags
    |> add_mention_tags
    |> add_emoji_tags
    |> add_attributed_to
    |> prepare_attachments
    |> set_conversation
    |> set_reply_to_uri
    |> set_replies
    |> strip_internal_fields
    |> strip_internal_tags
    |> set_type
  end

  def prepare_outgoing(%{"type" => activity_type, "object" => object_id} = data)
      when activity_type in ["Create", "Listen"] do
    object =
      object_id
      |> Object.normalize()
      |> Map.get(:data)
      |> prepare_object

    data =
      data
      |> Map.put("object", object)
      |> Map.merge(Builder.json_ld_header())
      |> Map.delete("bcc")

    {:ok, data}
  end

  def prepare_outgoing(%{"type" => "Announce", "actor" => ap_id, "object" => object_id} = data) do
    object =
      object_id
      |> Object.normalize()

    data =
      if Visibility.is_private?(object) && object.data["actor"] == ap_id do
        data |> Map.put("object", object |> Map.get(:data) |> prepare_object)
      else
        data |> maybe_fix_object_url
      end

    data =
      data
      |> strip_internal_fields
      |> Map.merge(Builder.json_ld_header())
      |> Map.delete("bcc")

    {:ok, data}
  end

  # Mastodon Accept/Reject requires a non-normalized object containing the actor URIs,
  # because of course it does.
  def prepare_outgoing(%{"type" => "Accept"} = data) do
    with follow_activity <- Activity.normalize(data["object"]) do
      object = %{
        "actor" => follow_activity.actor,
        "object" => follow_activity.data["object"],
        "id" => follow_activity.data["id"],
        "type" => "Follow"
      }

      data =
        data
        |> Map.put("object", object)
        |> Map.merge(Builder.json_ld_header())

      {:ok, data}
    end
  end

  def prepare_outgoing(%{"type" => "Reject"} = data) do
    with follow_activity <- Activity.normalize(data["object"]) do
      object = %{
        "actor" => follow_activity.actor,
        "object" => follow_activity.data["object"],
        "id" => follow_activity.data["id"],
        "type" => "Follow"
      }

      data =
        data
        |> Map.put("object", object)
        |> Map.merge(Builder.json_ld_header())

      {:ok, data}
    end
  end

  def prepare_outgoing(%{"type" => _type} = data) do
    data =
      data
      |> strip_internal_fields
      |> maybe_fix_object_url
      |> Map.merge(Builder.json_ld_header())

    {:ok, data}
  end

  defp maybe_fix_object_url(%{"object" => object} = data) when is_binary(object) do
    with false <- String.starts_with?(object, "http"),
         {:fetch, {:ok, relative_object}} <- {:fetch, get_obj_helper(object)},
         %{data: %{"external_url" => external_url}} when not is_nil(external_url) <-
           relative_object do
      Map.put(data, "object", external_url)
    else
      {:fetch, e} ->
        Logger.error("Couldn't fetch #{object} #{inspect(e)}")
        data

      _ ->
        data
    end
  end

  defp maybe_fix_object_url(data), do: data

  defp add_hashtags(object) do
    tags =
      ((object["hashtags"] || []) ++ (object["tag"] || []))
      |> Enum.map(fn
        # Expand internal representation tags into AS2 tags.
        tag when is_binary(tag) ->
          %{
            "href" => Pleroma.Web.Endpoint.url() <> "/tags/#{tag}",
            "name" => "##{tag}",
            "type" => "Hashtag"
          }

        # Do not process tags which are already AS2 tag objects.
        tag when is_map(tag) ->
          tag
      end)

    Map.put(object, "tag", tags)
  end

  # TODO These should be added on our side on insertion, it doesn't make much
  # sense to regenerate these all the time
  defp add_mention_tags(object) do
    to = object["to"] || []
    cc = object["cc"] || []
    mentioned = User.get_users_from_set(to ++ cc, local_only: false)

    mentions = Enum.map(mentioned, &build_mention_tag/1)

    tags = object["tag"] || []
    Map.put(object, "tag", tags ++ mentions)
  end

  defp build_mention_tag(%{ap_id: ap_id, nickname: nickname} = _) do
    %{"type" => "Mention", "href" => ap_id, "name" => "@#{nickname}"}
  end

  def take_emoji_tags(%User{emoji: emoji}) do
    emoji
    |> Map.to_list()
    |> Enum.map(&build_emoji_tag/1)
  end

  # TODO: we should probably send mtime instead of unix epoch time for updated
  defp add_emoji_tags(%{"emoji" => emoji} = object) do
    tags = object["tag"] || []

    out = Enum.map(emoji, &build_emoji_tag/1)

    Map.put(object, "tag", tags ++ out)
  end

  defp add_emoji_tags(object), do: object

  defp build_emoji_tag({name, url}) do
    %{
      "icon" => %{"url" => url, "type" => "Image"},
      "name" => ":" <> name <> ":",
      "type" => "Emoji",
      "updated" => "1970-01-01T00:00:00Z",
      "id" => url
    }
  end

  defp set_conversation(object) do
    Map.put(object, "conversation", object["context"])
  end

  def set_sensitive(%{"sensitive" => _} = object) do
    object
  end

  def set_sensitive(object) do
    tags = object["hashtags"] || object["tag"] || []
    Map.put(object, "sensitive", "nsfw" in tags)
  end

  defp set_type(%{"type" => "Answer"} = object) do
    Map.put(object, "type", "Note")
  end

  defp set_type(object), do: object

  defp add_attributed_to(object) do
    attributed_to = object["attributedTo"] || object["actor"]
    Map.put(object, "attributedTo", attributed_to)
  end

  # TODO: Revisit this
  defp prepare_attachments(%{"type" => "ChatMessage"} = object), do: object

  defp prepare_attachments(object) do
    attachments =
      object
      |> Map.get("attachment", [])
      |> Enum.map(fn data ->
        [%{"mediaType" => media_type, "href" => href} | _] = data["url"]

        %{
          "url" => href,
          "mediaType" => media_type,
          "name" => data["name"],
          "type" => "Document"
        }
      end)

    Map.put(object, "attachment", attachments)
  end

  def strip_internal_fields(object) do
    Map.drop(object, Pleroma.Constants.object_internal_fields())
  end

  defp strip_internal_tags(%{"tag" => tags} = object) do
    tags = Enum.filter(tags, fn x -> is_map(x) end)

    Map.put(object, "tag", tags)
  end

  defp strip_internal_tags(object), do: object

  def perform(:user_upgrade, user) do
    # we pass a fake user so that the followers collection is stripped away
    old_follower_address = User.ap_followers(%User{nickname: user.nickname})

    from(
      a in Activity,
      where: ^old_follower_address in a.recipients,
      update: [
        set: [
          recipients:
            fragment(
              "array_replace(?,?,?)",
              a.recipients,
              ^old_follower_address,
              ^user.follower_address
            )
        ]
      ]
    )
    |> Repo.update_all([])
  end

  def upgrade_user_from_ap_id(ap_id) do
    with %User{local: false} = user <- User.get_cached_by_ap_id(ap_id),
         {:ok, data} <- ActivityPub.fetch_and_prepare_user_from_ap_id(ap_id),
         {:ok, user} <- update_user(user, data) do
      TransmogrifierWorker.enqueue("user_upgrade", %{"user_id" => user.id})
      {:ok, user}
    else
      %User{} = user -> {:ok, user}
      e -> e
    end
  end

  defp update_user(user, data) do
    user
    |> User.remote_user_changeset(data)
    |> User.update_and_set_cache()
  end

  defp maybe_fix_user_url(%{"url" => url} = data) when is_map(url) do
    Map.put(data, "url", url["href"])
  end

  defp maybe_fix_user_url(data), do: data

  def maybe_fix_user_object(data), do: maybe_fix_user_url(data)
end
