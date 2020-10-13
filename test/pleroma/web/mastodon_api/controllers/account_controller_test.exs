# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.AccountControllerTest do
  use Pleroma.Web.ConnCase

  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.InternalFetchActor
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  describe "account fetching" do
    test "works by id" do
      %User{id: user_id} = insert(:user)

      assert %{"id" => ^user_id} =
               build_conn()
               |> get("/api/v1/accounts/#{user_id}")
               |> json_response_and_validate_schema(200)

      assert %{"error" => "Can't find user"} =
               build_conn()
               |> get("/api/v1/accounts/-1")
               |> json_response_and_validate_schema(404)
    end

    test "works by nickname" do
      user = insert(:user)

      assert %{"id" => user_id} =
               build_conn()
               |> get("/api/v1/accounts/#{user.nickname}")
               |> json_response_and_validate_schema(200)
    end

    test "works by nickname for remote users" do
      clear_config([:instance, :limit_to_local_content], false)

      user = insert(:user, nickname: "user@example.com", local: false)

      assert %{"id" => user_id} =
               build_conn()
               |> get("/api/v1/accounts/#{user.nickname}")
               |> json_response_and_validate_schema(200)
    end

    test "respects limit_to_local_content == :all for remote user nicknames" do
      clear_config([:instance, :limit_to_local_content], :all)

      user = insert(:user, nickname: "user@example.com", local: false)

      assert build_conn()
             |> get("/api/v1/accounts/#{user.nickname}")
             |> json_response_and_validate_schema(404)
    end

    test "respects limit_to_local_content == :unauthenticated for remote user nicknames" do
      clear_config([:instance, :limit_to_local_content], :unauthenticated)

      user = insert(:user, nickname: "user@example.com", local: false)
      reading_user = insert(:user)

      conn =
        build_conn()
        |> get("/api/v1/accounts/#{user.nickname}")

      assert json_response_and_validate_schema(conn, 404)

      conn =
        build_conn()
        |> assign(:user, reading_user)
        |> assign(:token, insert(:oauth_token, user: reading_user, scopes: ["read:accounts"]))
        |> get("/api/v1/accounts/#{user.nickname}")

      assert %{"id" => id} = json_response_and_validate_schema(conn, 200)
      assert id == user.id
    end

    test "accounts fetches correct account for nicknames beginning with numbers", %{conn: conn} do
      # Need to set an old-style integer ID to reproduce the problem
      # (these are no longer assigned to new accounts but were preserved
      # for existing accounts during the migration to flakeIDs)
      user_one = insert(:user, %{id: 1212})
      user_two = insert(:user, %{nickname: "#{user_one.id}garbage"})

      acc_one =
        conn
        |> get("/api/v1/accounts/#{user_one.id}")
        |> json_response_and_validate_schema(:ok)

      acc_two =
        conn
        |> get("/api/v1/accounts/#{user_two.nickname}")
        |> json_response_and_validate_schema(:ok)

      acc_three =
        conn
        |> get("/api/v1/accounts/#{user_two.id}")
        |> json_response_and_validate_schema(:ok)

      refute acc_one == acc_two
      assert acc_two == acc_three
    end

    test "returns 404 when user is invisible", %{conn: conn} do
      user = insert(:user, %{invisible: true})

      assert %{"error" => "Can't find user"} =
               conn
               |> get("/api/v1/accounts/#{user.nickname}")
               |> json_response_and_validate_schema(404)
    end

    test "returns 404 for internal.fetch actor", %{conn: conn} do
      %User{nickname: "internal.fetch"} = InternalFetchActor.get_actor()

      assert %{"error" => "Can't find user"} =
               conn
               |> get("/api/v1/accounts/internal.fetch")
               |> json_response_and_validate_schema(404)
    end

    test "returns 404 for deactivated user", %{conn: conn} do
      user = insert(:user, deactivated: true)

      assert %{"error" => "Can't find user"} =
               conn
               |> get("/api/v1/accounts/#{user.id}")
               |> json_response_and_validate_schema(:not_found)
    end
  end

  defp local_and_remote_users do
    local = insert(:user)
    remote = insert(:user, local: false)
    {:ok, local: local, remote: remote}
  end

  describe "user fetching with restrict unauthenticated profiles for local and remote" do
    setup do: local_and_remote_users()

    setup do: clear_config([:restrict_unauthenticated, :profiles, :local], true)

    setup do: clear_config([:restrict_unauthenticated, :profiles, :remote], true)

    test "if user is unauthenticated", %{conn: conn, local: local, remote: remote} do
      assert %{"error" => "This API requires an authenticated user"} ==
               conn
               |> get("/api/v1/accounts/#{local.id}")
               |> json_response_and_validate_schema(:unauthorized)

      assert %{"error" => "This API requires an authenticated user"} ==
               conn
               |> get("/api/v1/accounts/#{remote.id}")
               |> json_response_and_validate_schema(:unauthorized)
    end

    test "if user is authenticated", %{local: local, remote: remote} do
      %{conn: conn} = oauth_access(["read"])

      res_conn = get(conn, "/api/v1/accounts/#{local.id}")
      assert %{"id" => _} = json_response_and_validate_schema(res_conn, 200)

      res_conn = get(conn, "/api/v1/accounts/#{remote.id}")
      assert %{"id" => _} = json_response_and_validate_schema(res_conn, 200)
    end
  end

  describe "user fetching with restrict unauthenticated profiles for local" do
    setup do: local_and_remote_users()

    setup do: clear_config([:restrict_unauthenticated, :profiles, :local], true)

    test "if user is unauthenticated", %{conn: conn, local: local, remote: remote} do
      res_conn = get(conn, "/api/v1/accounts/#{local.id}")

      assert json_response_and_validate_schema(res_conn, :unauthorized) == %{
               "error" => "This API requires an authenticated user"
             }

      res_conn = get(conn, "/api/v1/accounts/#{remote.id}")
      assert %{"id" => _} = json_response_and_validate_schema(res_conn, 200)
    end

    test "if user is authenticated", %{local: local, remote: remote} do
      %{conn: conn} = oauth_access(["read"])

      res_conn = get(conn, "/api/v1/accounts/#{local.id}")
      assert %{"id" => _} = json_response_and_validate_schema(res_conn, 200)

      res_conn = get(conn, "/api/v1/accounts/#{remote.id}")
      assert %{"id" => _} = json_response_and_validate_schema(res_conn, 200)
    end
  end

  describe "user fetching with restrict unauthenticated profiles for remote" do
    setup do: local_and_remote_users()

    setup do: clear_config([:restrict_unauthenticated, :profiles, :remote], true)

    test "if user is unauthenticated", %{conn: conn, local: local, remote: remote} do
      res_conn = get(conn, "/api/v1/accounts/#{local.id}")
      assert %{"id" => _} = json_response_and_validate_schema(res_conn, 200)

      res_conn = get(conn, "/api/v1/accounts/#{remote.id}")

      assert json_response_and_validate_schema(res_conn, :unauthorized) == %{
               "error" => "This API requires an authenticated user"
             }
    end

    test "if user is authenticated", %{local: local, remote: remote} do
      %{conn: conn} = oauth_access(["read"])

      res_conn = get(conn, "/api/v1/accounts/#{local.id}")
      assert %{"id" => _} = json_response_and_validate_schema(res_conn, 200)

      res_conn = get(conn, "/api/v1/accounts/#{remote.id}")
      assert %{"id" => _} = json_response_and_validate_schema(res_conn, 200)
    end
  end

  describe "user timelines" do
    setup do: oauth_access(["read:statuses"])

    test "works with announces that are just addressed to public", %{conn: conn} do
      user = insert(:user, ap_id: "https://honktest/u/test", local: false)
      other_user = insert(:user)

      {:ok, post} = CommonAPI.post(other_user, %{status: "bonkeronk"})

      {:ok, announce, _} =
        %{
          "@context" => "https://www.w3.org/ns/activitystreams",
          "actor" => "https://honktest/u/test",
          "id" => "https://honktest/u/test/bonk/1793M7B9MQ48847vdx",
          "object" => post.data["object"],
          "published" => "2019-06-25T19:33:58Z",
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "type" => "Announce"
        }
        |> ActivityPub.persist(local: false)

      assert resp =
               conn
               |> get("/api/v1/accounts/#{user.id}/statuses")
               |> json_response_and_validate_schema(200)

      assert [%{"id" => id}] = resp
      assert id == announce.id
    end

    test "deactivated user", %{conn: conn} do
      user = insert(:user, deactivated: true)

      assert %{"error" => "Can't find user"} ==
               conn
               |> get("/api/v1/accounts/#{user.id}/statuses")
               |> json_response_and_validate_schema(:not_found)
    end

    test "returns 404 when user is invisible", %{conn: conn} do
      user = insert(:user, %{invisible: true})

      assert %{"error" => "Can't find user"} =
               conn
               |> get("/api/v1/accounts/#{user.id}")
               |> json_response_and_validate_schema(404)
    end

    test "respects blocks", %{user: user_one, conn: conn} do
      user_two = insert(:user)
      user_three = insert(:user)

      User.block(user_one, user_two)

      {:ok, activity} = CommonAPI.post(user_two, %{status: "User one sux0rz"})
      {:ok, repeat} = CommonAPI.repeat(activity.id, user_three)

      assert resp =
               conn
               |> get("/api/v1/accounts/#{user_two.id}/statuses")
               |> json_response_and_validate_schema(200)

      assert [%{"id" => id}] = resp
      assert id == activity.id

      # Even a blocked user will deliver the full user timeline, there would be
      #   no point in looking at a blocked users timeline otherwise
      assert resp =
               conn
               |> get("/api/v1/accounts/#{user_two.id}/statuses")
               |> json_response_and_validate_schema(200)

      assert [%{"id" => id}] = resp
      assert id == activity.id

      # Third user's timeline includes the repeat when viewed by unauthenticated user
      resp =
        build_conn()
        |> get("/api/v1/accounts/#{user_three.id}/statuses")
        |> json_response_and_validate_schema(200)

      assert [%{"id" => id}] = resp
      assert id == repeat.id

      # When viewing a third user's timeline, the blocked users' statuses will NOT be shown
      resp = get(conn, "/api/v1/accounts/#{user_three.id}/statuses")

      assert [] == json_response_and_validate_schema(resp, 200)
    end

    test "gets users statuses", %{conn: conn} do
      user_one = insert(:user)
      user_two = insert(:user)
      user_three = insert(:user)

      {:ok, _user_three} = User.follow(user_three, user_one)

      {:ok, activity} = CommonAPI.post(user_one, %{status: "HI!!!"})

      {:ok, direct_activity} =
        CommonAPI.post(user_one, %{
          status: "Hi, @#{user_two.nickname}.",
          visibility: "direct"
        })

      {:ok, private_activity} =
        CommonAPI.post(user_one, %{status: "private", visibility: "private"})

      # TODO!!!
      resp =
        conn
        |> get("/api/v1/accounts/#{user_one.id}/statuses")
        |> json_response_and_validate_schema(200)

      assert [%{"id" => id}] = resp
      assert id == to_string(activity.id)

      resp =
        conn
        |> assign(:user, user_two)
        |> assign(:token, insert(:oauth_token, user: user_two, scopes: ["read:statuses"]))
        |> get("/api/v1/accounts/#{user_one.id}/statuses")
        |> json_response_and_validate_schema(200)

      assert [%{"id" => id_one}, %{"id" => id_two}] = resp
      assert id_one == to_string(direct_activity.id)
      assert id_two == to_string(activity.id)

      resp =
        conn
        |> assign(:user, user_three)
        |> assign(:token, insert(:oauth_token, user: user_three, scopes: ["read:statuses"]))
        |> get("/api/v1/accounts/#{user_one.id}/statuses")
        |> json_response_and_validate_schema(200)

      assert [%{"id" => id_one}, %{"id" => id_two}] = resp
      assert id_one == to_string(private_activity.id)
      assert id_two == to_string(activity.id)
    end

    test "unimplemented pinned statuses feature", %{conn: conn} do
      note = insert(:note_activity)
      user = User.get_cached_by_ap_id(note.data["actor"])

      conn = get(conn, "/api/v1/accounts/#{user.id}/statuses?pinned=true")

      assert json_response_and_validate_schema(conn, 200) == []
    end

    test "gets an users media, excludes reblogs", %{conn: conn} do
      note = insert(:note_activity)
      user = User.get_cached_by_ap_id(note.data["actor"])
      other_user = insert(:user)

      file = %Plug.Upload{
        content_type: "image/jpg",
        path: Path.absname("test/fixtures/image.jpg"),
        filename: "an_image.jpg"
      }

      {:ok, %{id: media_id}} = ActivityPub.upload(file, actor: user.ap_id)

      {:ok, %{id: image_post_id}} = CommonAPI.post(user, %{status: "cofe", media_ids: [media_id]})

      {:ok, %{id: media_id}} = ActivityPub.upload(file, actor: other_user.ap_id)

      {:ok, %{id: other_image_post_id}} =
        CommonAPI.post(other_user, %{status: "cofe2", media_ids: [media_id]})

      {:ok, _announce} = CommonAPI.repeat(other_image_post_id, user)

      conn = get(conn, "/api/v1/accounts/#{user.id}/statuses?only_media=true")

      assert [%{"id" => ^image_post_id}] = json_response_and_validate_schema(conn, 200)

      conn = get(build_conn(), "/api/v1/accounts/#{user.id}/statuses?only_media=1")

      assert [%{"id" => ^image_post_id}] = json_response_and_validate_schema(conn, 200)
    end

    test "gets a user's statuses without reblogs", %{user: user, conn: conn} do
      {:ok, %{id: post_id}} = CommonAPI.post(user, %{status: "HI!!!"})
      {:ok, _} = CommonAPI.repeat(post_id, user)

      conn = get(conn, "/api/v1/accounts/#{user.id}/statuses?exclude_reblogs=true")
      assert [%{"id" => ^post_id}] = json_response_and_validate_schema(conn, 200)

      conn = get(conn, "/api/v1/accounts/#{user.id}/statuses?exclude_reblogs=1")
      assert [%{"id" => ^post_id}] = json_response_and_validate_schema(conn, 200)
    end

    test "filters user's statuses by a hashtag", %{user: user, conn: conn} do
      {:ok, %{id: post_id}} = CommonAPI.post(user, %{status: "#hashtag"})
      {:ok, _post} = CommonAPI.post(user, %{status: "hashtag"})

      conn = get(conn, "/api/v1/accounts/#{user.id}/statuses?tagged=hashtag")
      assert [%{"id" => ^post_id}] = json_response_and_validate_schema(conn, 200)
    end

    test "the user views their own timelines and excludes direct messages", %{
      user: user,
      conn: conn
    } do
      {:ok, %{id: public_activity_id}} =
        CommonAPI.post(user, %{status: ".", visibility: "public"})

      {:ok, _direct_activity} = CommonAPI.post(user, %{status: ".", visibility: "direct"})

      conn = get(conn, "/api/v1/accounts/#{user.id}/statuses?exclude_visibilities[]=direct")
      assert [%{"id" => ^public_activity_id}] = json_response_and_validate_schema(conn, 200)
    end
  end

  defp local_and_remote_activities(%{local: local, remote: remote}) do
    insert(:note_activity, user: local)
    insert(:note_activity, user: remote, local: false)

    :ok
  end

  describe "statuses with restrict unauthenticated profiles for local and remote" do
    setup do: local_and_remote_users()
    setup :local_and_remote_activities

    setup do: clear_config([:restrict_unauthenticated, :profiles, :local], true)

    setup do: clear_config([:restrict_unauthenticated, :profiles, :remote], true)

    test "if user is unauthenticated", %{conn: conn, local: local, remote: remote} do
      assert %{"error" => "This API requires an authenticated user"} ==
               conn
               |> get("/api/v1/accounts/#{local.id}/statuses")
               |> json_response_and_validate_schema(:unauthorized)

      assert %{"error" => "This API requires an authenticated user"} ==
               conn
               |> get("/api/v1/accounts/#{remote.id}/statuses")
               |> json_response_and_validate_schema(:unauthorized)
    end

    test "if user is authenticated", %{local: local, remote: remote} do
      %{conn: conn} = oauth_access(["read"])

      res_conn = get(conn, "/api/v1/accounts/#{local.id}/statuses")
      assert length(json_response_and_validate_schema(res_conn, 200)) == 1

      res_conn = get(conn, "/api/v1/accounts/#{remote.id}/statuses")
      assert length(json_response_and_validate_schema(res_conn, 200)) == 1
    end
  end

  describe "statuses with restrict unauthenticated profiles for local" do
    setup do: local_and_remote_users()
    setup :local_and_remote_activities

    setup do: clear_config([:restrict_unauthenticated, :profiles, :local], true)

    test "if user is unauthenticated", %{conn: conn, local: local, remote: remote} do
      assert %{"error" => "This API requires an authenticated user"} ==
               conn
               |> get("/api/v1/accounts/#{local.id}/statuses")
               |> json_response_and_validate_schema(:unauthorized)

      res_conn = get(conn, "/api/v1/accounts/#{remote.id}/statuses")
      assert length(json_response_and_validate_schema(res_conn, 200)) == 1
    end

    test "if user is authenticated", %{local: local, remote: remote} do
      %{conn: conn} = oauth_access(["read"])

      res_conn = get(conn, "/api/v1/accounts/#{local.id}/statuses")
      assert length(json_response_and_validate_schema(res_conn, 200)) == 1

      res_conn = get(conn, "/api/v1/accounts/#{remote.id}/statuses")
      assert length(json_response_and_validate_schema(res_conn, 200)) == 1
    end
  end

  describe "statuses with restrict unauthenticated profiles for remote" do
    setup do: local_and_remote_users()
    setup :local_and_remote_activities

    setup do: clear_config([:restrict_unauthenticated, :profiles, :remote], true)

    test "if user is unauthenticated", %{conn: conn, local: local, remote: remote} do
      res_conn = get(conn, "/api/v1/accounts/#{local.id}/statuses")
      assert length(json_response_and_validate_schema(res_conn, 200)) == 1

      assert %{"error" => "This API requires an authenticated user"} ==
               conn
               |> get("/api/v1/accounts/#{remote.id}/statuses")
               |> json_response_and_validate_schema(:unauthorized)
    end

    test "if user is authenticated", %{local: local, remote: remote} do
      %{conn: conn} = oauth_access(["read"])

      res_conn = get(conn, "/api/v1/accounts/#{local.id}/statuses")
      assert length(json_response_and_validate_schema(res_conn, 200)) == 1

      res_conn = get(conn, "/api/v1/accounts/#{remote.id}/statuses")
      assert length(json_response_and_validate_schema(res_conn, 200)) == 1
    end
  end

  describe "followers" do
    setup do: oauth_access(["read:accounts"])

    test "getting followers", %{user: user, conn: conn} do
      other_user = insert(:user)
      {:ok, %{id: user_id}} = User.follow(user, other_user)

      conn = get(conn, "/api/v1/accounts/#{other_user.id}/followers")

      assert [%{"id" => ^user_id}] = json_response_and_validate_schema(conn, 200)
    end

    test "getting followers, hide_followers", %{user: user, conn: conn} do
      other_user = insert(:user, hide_followers: true)
      {:ok, _user} = User.follow(user, other_user)

      conn = get(conn, "/api/v1/accounts/#{other_user.id}/followers")

      assert [] == json_response_and_validate_schema(conn, 200)
    end

    test "getting followers, hide_followers, same user requesting" do
      user = insert(:user)
      other_user = insert(:user, hide_followers: true)
      {:ok, _user} = User.follow(user, other_user)

      conn =
        build_conn()
        |> assign(:user, other_user)
        |> assign(:token, insert(:oauth_token, user: other_user, scopes: ["read:accounts"]))
        |> get("/api/v1/accounts/#{other_user.id}/followers")

      refute [] == json_response_and_validate_schema(conn, 200)
    end

    test "getting followers, pagination", %{user: user, conn: conn} do
      {:ok, %User{id: follower1_id}} = :user |> insert() |> User.follow(user)
      {:ok, %User{id: follower2_id}} = :user |> insert() |> User.follow(user)
      {:ok, %User{id: follower3_id}} = :user |> insert() |> User.follow(user)

      assert [%{"id" => ^follower3_id}, %{"id" => ^follower2_id}] =
               conn
               |> get("/api/v1/accounts/#{user.id}/followers?since_id=#{follower1_id}")
               |> json_response_and_validate_schema(200)

      assert [%{"id" => ^follower2_id}, %{"id" => ^follower1_id}] =
               conn
               |> get("/api/v1/accounts/#{user.id}/followers?max_id=#{follower3_id}")
               |> json_response_and_validate_schema(200)

      assert [%{"id" => ^follower2_id}, %{"id" => ^follower1_id}] =
               conn
               |> get(
                 "/api/v1/accounts/#{user.id}/followers?id=#{user.id}&limit=20&max_id=#{
                   follower3_id
                 }"
               )
               |> json_response_and_validate_schema(200)

      res_conn = get(conn, "/api/v1/accounts/#{user.id}/followers?limit=1&max_id=#{follower3_id}")

      assert [%{"id" => ^follower2_id}] = json_response_and_validate_schema(res_conn, 200)

      assert [link_header] = get_resp_header(res_conn, "link")
      assert link_header =~ ~r/min_id=#{follower2_id}/
      assert link_header =~ ~r/max_id=#{follower2_id}/
    end
  end

  describe "following" do
    setup do: oauth_access(["read:accounts"])

    test "getting following", %{user: user, conn: conn} do
      other_user = insert(:user)
      {:ok, user} = User.follow(user, other_user)

      conn = get(conn, "/api/v1/accounts/#{user.id}/following")

      assert [%{"id" => id}] = json_response_and_validate_schema(conn, 200)
      assert id == to_string(other_user.id)
    end

    test "getting following, hide_follows, other user requesting" do
      user = insert(:user, hide_follows: true)
      other_user = insert(:user)
      {:ok, user} = User.follow(user, other_user)

      conn =
        build_conn()
        |> assign(:user, other_user)
        |> assign(:token, insert(:oauth_token, user: other_user, scopes: ["read:accounts"]))
        |> get("/api/v1/accounts/#{user.id}/following")

      assert [] == json_response_and_validate_schema(conn, 200)
    end

    test "getting following, hide_follows, same user requesting" do
      user = insert(:user, hide_follows: true)
      other_user = insert(:user)
      {:ok, user} = User.follow(user, other_user)

      conn =
        build_conn()
        |> assign(:user, user)
        |> assign(:token, insert(:oauth_token, user: user, scopes: ["read:accounts"]))
        |> get("/api/v1/accounts/#{user.id}/following")

      refute [] == json_response_and_validate_schema(conn, 200)
    end

    test "getting following, pagination", %{user: user, conn: conn} do
      following1 = insert(:user)
      following2 = insert(:user)
      following3 = insert(:user)
      {:ok, _} = User.follow(user, following1)
      {:ok, _} = User.follow(user, following2)
      {:ok, _} = User.follow(user, following3)

      res_conn = get(conn, "/api/v1/accounts/#{user.id}/following?since_id=#{following1.id}")

      assert [%{"id" => id3}, %{"id" => id2}] = json_response_and_validate_schema(res_conn, 200)
      assert id3 == following3.id
      assert id2 == following2.id

      res_conn = get(conn, "/api/v1/accounts/#{user.id}/following?max_id=#{following3.id}")

      assert [%{"id" => id2}, %{"id" => id1}] = json_response_and_validate_schema(res_conn, 200)
      assert id2 == following2.id
      assert id1 == following1.id

      res_conn =
        get(
          conn,
          "/api/v1/accounts/#{user.id}/following?id=#{user.id}&limit=20&max_id=#{following3.id}"
        )

      assert [%{"id" => id2}, %{"id" => id1}] = json_response_and_validate_schema(res_conn, 200)
      assert id2 == following2.id
      assert id1 == following1.id

      res_conn =
        get(conn, "/api/v1/accounts/#{user.id}/following?limit=1&max_id=#{following3.id}")

      assert [%{"id" => id2}] = json_response_and_validate_schema(res_conn, 200)
      assert id2 == following2.id

      assert [link_header] = get_resp_header(res_conn, "link")
      assert link_header =~ ~r/min_id=#{following2.id}/
      assert link_header =~ ~r/max_id=#{following2.id}/
    end
  end

  describe "follow/unfollow" do
    setup do: oauth_access(["follow"])

    test "following / unfollowing a user", %{conn: conn} do
      %{id: other_user_id, nickname: other_user_nickname} = insert(:user)

      assert %{"id" => _id, "following" => true} =
               conn
               |> post("/api/v1/accounts/#{other_user_id}/follow")
               |> json_response_and_validate_schema(200)

      assert %{"id" => _id, "following" => false} =
               conn
               |> post("/api/v1/accounts/#{other_user_id}/unfollow")
               |> json_response_and_validate_schema(200)

      assert %{"id" => ^other_user_id} =
               conn
               |> put_req_header("content-type", "application/json")
               |> post("/api/v1/follows", %{"uri" => other_user_nickname})
               |> json_response_and_validate_schema(200)
    end

    test "cancelling follow request", %{conn: conn} do
      %{id: other_user_id} = insert(:user, %{locked: true})

      assert %{"id" => ^other_user_id, "following" => false, "requested" => true} =
               conn
               |> post("/api/v1/accounts/#{other_user_id}/follow")
               |> json_response_and_validate_schema(:ok)

      assert %{"id" => ^other_user_id, "following" => false, "requested" => false} =
               conn
               |> post("/api/v1/accounts/#{other_user_id}/unfollow")
               |> json_response_and_validate_schema(:ok)
    end

    test "following without reblogs" do
      %{conn: conn} = oauth_access(["follow", "read:statuses"])
      followed = insert(:user)
      other_user = insert(:user)

      ret_conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/accounts/#{followed.id}/follow", %{reblogs: false})

      assert %{"showing_reblogs" => false} = json_response_and_validate_schema(ret_conn, 200)

      {:ok, activity} = CommonAPI.post(other_user, %{status: "hey"})
      {:ok, %{id: reblog_id}} = CommonAPI.repeat(activity.id, followed)

      assert [] ==
               conn
               |> get("/api/v1/timelines/home")
               |> json_response(200)

      assert %{"showing_reblogs" => true} =
               conn
               |> put_req_header("content-type", "application/json")
               |> post("/api/v1/accounts/#{followed.id}/follow", %{reblogs: true})
               |> json_response_and_validate_schema(200)

      assert [%{"id" => ^reblog_id}] =
               conn
               |> get("/api/v1/timelines/home")
               |> json_response(200)
    end

    test "following with reblogs" do
      %{conn: conn} = oauth_access(["follow", "read:statuses"])
      followed = insert(:user)
      other_user = insert(:user)

      ret_conn = post(conn, "/api/v1/accounts/#{followed.id}/follow")

      assert %{"showing_reblogs" => true} = json_response_and_validate_schema(ret_conn, 200)

      {:ok, activity} = CommonAPI.post(other_user, %{status: "hey"})
      {:ok, %{id: reblog_id}} = CommonAPI.repeat(activity.id, followed)

      assert [%{"id" => ^reblog_id}] =
               conn
               |> get("/api/v1/timelines/home")
               |> json_response(200)

      assert %{"showing_reblogs" => false} =
               conn
               |> put_req_header("content-type", "application/json")
               |> post("/api/v1/accounts/#{followed.id}/follow", %{reblogs: false})
               |> json_response_and_validate_schema(200)

      assert [] ==
               conn
               |> get("/api/v1/timelines/home")
               |> json_response(200)
    end

    test "following / unfollowing errors", %{user: user, conn: conn} do
      # self follow
      conn_res = post(conn, "/api/v1/accounts/#{user.id}/follow")

      assert %{"error" => "Can not follow yourself"} =
               json_response_and_validate_schema(conn_res, 400)

      # self unfollow
      user = User.get_cached_by_id(user.id)
      conn_res = post(conn, "/api/v1/accounts/#{user.id}/unfollow")

      assert %{"error" => "Can not unfollow yourself"} =
               json_response_and_validate_schema(conn_res, 400)

      # self follow via uri
      user = User.get_cached_by_id(user.id)

      assert %{"error" => "Can not follow yourself"} =
               conn
               |> put_req_header("content-type", "multipart/form-data")
               |> post("/api/v1/follows", %{"uri" => user.nickname})
               |> json_response_and_validate_schema(400)

      # follow non existing user
      conn_res = post(conn, "/api/v1/accounts/doesntexist/follow")
      assert %{"error" => "Record not found"} = json_response_and_validate_schema(conn_res, 404)

      # follow non existing user via uri
      conn_res =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v1/follows", %{"uri" => "doesntexist"})

      assert %{"error" => "Record not found"} = json_response_and_validate_schema(conn_res, 404)

      # unfollow non existing user
      conn_res = post(conn, "/api/v1/accounts/doesntexist/unfollow")
      assert %{"error" => "Record not found"} = json_response_and_validate_schema(conn_res, 404)
    end
  end

  describe "mute/unmute" do
    setup do: oauth_access(["write:mutes"])

    test "with notifications", %{conn: conn} do
      other_user = insert(:user)

      assert %{"id" => _id, "muting" => true, "muting_notifications" => true} =
               conn
               |> post("/api/v1/accounts/#{other_user.id}/mute")
               |> json_response_and_validate_schema(200)

      conn = post(conn, "/api/v1/accounts/#{other_user.id}/unmute")

      assert %{"id" => _id, "muting" => false, "muting_notifications" => false} =
               json_response_and_validate_schema(conn, 200)
    end

    test "without notifications", %{conn: conn} do
      other_user = insert(:user)

      ret_conn =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v1/accounts/#{other_user.id}/mute", %{"notifications" => "false"})

      assert %{"id" => _id, "muting" => true, "muting_notifications" => false} =
               json_response_and_validate_schema(ret_conn, 200)

      conn = post(conn, "/api/v1/accounts/#{other_user.id}/unmute")

      assert %{"id" => _id, "muting" => false, "muting_notifications" => false} =
               json_response_and_validate_schema(conn, 200)
    end
  end

  describe "pinned statuses" do
    setup do
      user = insert(:user)
      {:ok, activity} = CommonAPI.post(user, %{status: "HI!!!"})
      %{conn: conn} = oauth_access(["read:statuses"], user: user)

      [conn: conn, user: user, activity: activity]
    end

    test "returns pinned statuses", %{conn: conn, user: user, activity: %{id: activity_id}} do
      {:ok, _} = CommonAPI.pin(activity_id, user)

      assert [%{"id" => ^activity_id, "pinned" => true}] =
               conn
               |> get("/api/v1/accounts/#{user.id}/statuses?pinned=true")
               |> json_response_and_validate_schema(200)
    end
  end

  test "blocking / unblocking a user" do
    %{conn: conn} = oauth_access(["follow"])
    other_user = insert(:user)

    ret_conn = post(conn, "/api/v1/accounts/#{other_user.id}/block")

    assert %{"id" => _id, "blocking" => true} = json_response_and_validate_schema(ret_conn, 200)

    conn = post(conn, "/api/v1/accounts/#{other_user.id}/unblock")

    assert %{"id" => _id, "blocking" => false} = json_response_and_validate_schema(conn, 200)
  end

  describe "GET /api/v1/accounts/:id/lists - account_lists" do
    test "returns lists to which the account belongs" do
      %{user: user, conn: conn} = oauth_access(["read:lists"])
      other_user = insert(:user)
      assert {:ok, %Pleroma.List{id: list_id} = list} = Pleroma.List.create("Test List", user)
      {:ok, %{following: _following}} = Pleroma.List.follow(list, other_user)

      assert [%{"id" => list_id, "title" => "Test List"}] =
               conn
               |> get("/api/v1/accounts/#{other_user.id}/lists")
               |> json_response_and_validate_schema(200)
    end
  end

  describe "verify_credentials" do
    test "verify_credentials" do
      %{user: user, conn: conn} = oauth_access(["read:accounts"])

      [notification | _] =
        insert_list(7, :notification, user: user, activity: insert(:note_activity))

      Pleroma.Notification.set_read_up_to(user, notification.id)
      conn = get(conn, "/api/v1/accounts/verify_credentials")

      response = json_response_and_validate_schema(conn, 200)

      assert %{"id" => id, "source" => %{"privacy" => "public"}} = response
      assert response["pleroma"]["chat_token"]
      assert response["pleroma"]["unread_notifications_count"] == 6
      assert id == to_string(user.id)
    end

    test "verify_credentials default scope unlisted" do
      user = insert(:user, default_scope: "unlisted")
      %{conn: conn} = oauth_access(["read:accounts"], user: user)

      conn = get(conn, "/api/v1/accounts/verify_credentials")

      assert %{"id" => id, "source" => %{"privacy" => "unlisted"}} =
               json_response_and_validate_schema(conn, 200)

      assert id == to_string(user.id)
    end

    test "locked accounts" do
      user = insert(:user, default_scope: "private")
      %{conn: conn} = oauth_access(["read:accounts"], user: user)

      conn = get(conn, "/api/v1/accounts/verify_credentials")

      assert %{"id" => id, "source" => %{"privacy" => "private"}} =
               json_response_and_validate_schema(conn, 200)

      assert id == to_string(user.id)
    end
  end

  describe "user relationships" do
    setup do: oauth_access(["read:follows"])

    test "returns the relationships for the current user", %{user: user, conn: conn} do
      %{id: other_user_id} = other_user = insert(:user)
      {:ok, _user} = User.follow(user, other_user)

      assert [%{"id" => ^other_user_id}] =
               conn
               |> get("/api/v1/accounts/relationships?id=#{other_user.id}")
               |> json_response_and_validate_schema(200)

      assert [%{"id" => ^other_user_id}] =
               conn
               |> get("/api/v1/accounts/relationships?id[]=#{other_user.id}")
               |> json_response_and_validate_schema(200)
    end

    test "returns an empty list on a bad request", %{conn: conn} do
      conn = get(conn, "/api/v1/accounts/relationships", %{})

      assert [] = json_response_and_validate_schema(conn, 200)
    end
  end

  test "getting a list of mutes" do
    %{user: user, conn: conn} = oauth_access(["read:mutes"])
    other_user = insert(:user)

    {:ok, _user_relationships} = User.mute(user, other_user)

    conn = get(conn, "/api/v1/mutes")

    other_user_id = to_string(other_user.id)
    assert [%{"id" => ^other_user_id}] = json_response_and_validate_schema(conn, 200)
  end

  test "getting a list of blocks" do
    %{user: user, conn: conn} = oauth_access(["read:blocks"])
    other_user = insert(:user)

    {:ok, _user_relationship} = User.block(user, other_user)

    conn =
      conn
      |> assign(:user, user)
      |> get("/api/v1/blocks")

    other_user_id = to_string(other_user.id)
    assert [%{"id" => ^other_user_id}] = json_response_and_validate_schema(conn, 200)
  end
end
