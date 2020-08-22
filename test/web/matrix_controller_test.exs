# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MatrixControllerTest do
  use Pleroma.Web.ConnCase

  alias Pleroma.Web.CommonAPI
  alias Pleroma.Chat
  alias Pleroma.Chat.MessageReference
  alias Pleroma.Object
  import Pleroma.Factory

  describe "sync" do
    setup do
      %{user: user, conn: conn} = oauth_access(["read"])
      other_user = insert(:user)
      third_user = insert(:user)

      {:ok, chat_activity} = CommonAPI.post_chat_message(user, other_user, "Hey")
      {:ok, chat_activity_two} = CommonAPI.post_chat_message(third_user, user, "Henlo")

      chat = Chat.get(user.id, other_user.ap_id)
      chat_two = Chat.get(user.id, third_user.ap_id)

      chat_object = Object.normalize(chat_activity)
      cmr = MessageReference.for_chat_and_object(chat, chat_object)

      chat_object_two = Object.normalize(chat_activity_two)
      cmr_two = MessageReference.for_chat_and_object(chat_two, chat_object_two)

      %{
        user: user,
        other_user: other_user,
        third_user: third_user,
        conn: conn,
        chat_activity: chat_activity,
        chat_activity_two: chat_activity_two,
        chat: chat,
        chat_two: chat_two,
        cmr: cmr,
        cmr_two: cmr_two
      }
    end

    test "without options, it returns all chat messages the user has", %{
      conn: conn,
      chat: chat,
      chat_two: chat_two,
      cmr: cmr,
      cmr_two: cmr_two
    } do
      %{
        "next_batch" => next_batch,
        "rooms" => %{
          "join" => joined_rooms
        }
      } =
        conn
        |> get("_matrix/client/r0/sync")
        |> json_response(200)

      assert chat_room = joined_rooms[chat.id]
      assert chat_room_two = joined_rooms[chat_two.id]

      assert [message] = chat_room["timeline"]["events"]
      assert [message_two] = chat_room_two["timeline"]["events"]

      assert message["content"]["formatted_body"] == "Hey"
      assert message_two["content"]["formatted_body"] == "Henlo"

      assert message["event_id"] == cmr.id
      assert message_two["event_id"] == cmr_two.id

      # Next batch contains the largest ChatMessageReference id

      assert next_batch == cmr_two.id
    end

    test "given a `since` option, it only returns chat messages after that point", %{
      conn: conn,
      cmr_two: cmr_two,
      chat: chat,
      chat_two: chat_two,
      user: user,
      other_user: other_user
    } do
      {:ok, _} = CommonAPI.post_chat_message(user, other_user, "morning weebs")

      %{
        "rooms" => %{
          "join" => joined_rooms
        }
      } =
        conn
        |> get("_matrix/client/r0/sync?since=#{cmr_two.id}")
        |> json_response(200)

      refute joined_rooms[chat_two.id]
      assert chat_room = joined_rooms[chat.id]
      assert [message] = chat_room["timeline"]["events"]
      assert message["content"]["body"] == "morning weebs"
    end
  end
end
