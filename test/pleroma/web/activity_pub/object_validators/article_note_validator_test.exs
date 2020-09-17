# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.ArticleNoteValidatorTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ObjectValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.ArticleNoteValidator
  alias Pleroma.Web.ActivityPub.Utils

  import Pleroma.Factory

  setup_all do
    Tesla.Mock.mock_global(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  test "a basic note validates" do
    user = insert(:user)

    note = %{
      "id" => Utils.generate_activity_id(),
      "type" => "Note",
      "actor" => user.ap_id,
      "to" => [user.follower_address],
      "cc" => [],
      "content" => "Hellow this is content.",
      "context" => "xxx",
      "summary" => "a post"
    }

    %{valid?: true} = ArticleNoteValidator.cast_and_validate(note)
  end

  test "Mastodon Note" do
    data =
      File.read!("test/fixtures/mastodon-post-activity.json")
      |> Jason.decode!()

    {:ok, %User{}} = ObjectValidator.fetch_actor(data)

    assert %{changes: changes, valid?: true} =
             ArticleNoteValidator.cast_and_validate(data["object"])

    assert %{
             actor: "http://mastodon.example.org/users/admin",
             attributedTo: "http://mastodon.example.org/users/admin",
             cc: [
               "http://localtesting.pleroma.lol/users/lain",
               "http://mastodon.example.org/users/admin/followers"
             ],
             content:
               "<p><span class=\"h-card\"><a href=\"http://localtesting.pleroma.lol/users/lain\" class=\"u-url mention\">@<span>lain</span></a></span></p>",
             context: "tag:mastodon.example.org,2018-02-12:objectId=20:objectType=Conversation",
             id: "http://mastodon.example.org/users/admin/statuses/99512778738411822",
             published: "2018-02-12T14:08:20Z",
             sensitive: true,
             summary: "cw",
             tag: [
               %{
                 "href" => "http://localtesting.pleroma.lol/users/lain",
                 "name" => "@lain@localtesting.pleroma.lol",
                 "type" => "Mention"
               }
             ],
             to: ["https://www.w3.org/ns/activitystreams#Public"],
             type: "Note",
             url: "http://mastodon.example.org/@admin/99512778738411822",
             replies: [
               "http://mastodon.example.org/users/admin/statuses/99512778738411823",
               "http://mastodon.example.org/users/admin/statuses/99512778738411824"
             ]
           } = changes

    assert changes[:context_id]
  end
end
