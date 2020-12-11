# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.TransmogrifierTest do
  use Oban.Testing, repo: Pleroma.Repo
  use Pleroma.DataCase

  alias Pleroma.Object
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.AdminAPI.AccountView
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  test "it accepts Flag activities" do
    user = insert(:user)
    other_user = insert(:user)

    {:ok, activity} = CommonAPI.post(user, %{status: "test post"})
    object = Object.normalize(activity)

    note_obj = %{
      "type" => "Note",
      "id" => activity.data["id"],
      "content" => "test post",
      "published" => object.data["published"],
      "actor" => AccountView.render("show.json", %{user: user, skip_visibility_check: true})
    }

    message = %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "cc" => [user.ap_id],
      "object" => [user.ap_id, activity.data["id"]],
      "type" => "Flag",
      "content" => "blocked AND reported!!!",
      "actor" => other_user.ap_id
    }

    assert {:ok, activity} = Transmogrifier.handle_incoming(message)

    assert activity.data["object"] == [user.ap_id, note_obj]
    assert activity.data["content"] == "blocked AND reported!!!"
    assert activity.data["actor"] == other_user.ap_id
    assert activity.data["cc"] == [user.ap_id]
  end
end
