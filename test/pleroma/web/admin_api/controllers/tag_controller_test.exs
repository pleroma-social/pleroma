# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.AdminAPI.TagControllerTest do
  use Pleroma.Web.ConnCase
  use Oban.Testing, repo: Pleroma.Repo

  import Pleroma.Factory

  alias Pleroma.ModerationLog
  alias Pleroma.Repo
  alias Pleroma.User

  setup_all do
    Tesla.Mock.mock_global(fn env -> apply(HttpRequestMock, :request, [env]) end)

    :ok
  end

  setup do
    admin = insert(:user, is_admin: true)
    token = insert(:oauth_admin_token, user: admin)

    conn =
      build_conn()
      |> assign(:user, admin)
      |> assign(:token, token)

    {:ok, %{admin: admin, token: token, conn: conn}}
  end

  describe "GET /api/pleroma/admin/users/tag" do
    test "it returns user tags and mrf policy tags", %{conn: conn} do
      insert(:tag, name: "x")
      insert(:tag, name: "y")
      insert(:tag, name: "unchanged")

      response =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/api/pleroma/admin/users/tag")
        |> json_response(200)

      assert [
               "mrf_tag:disable-any-subscription",
               "mrf_tag:disable-remote-subscription",
               "mrf_tag:force-unlisted",
               "mrf_tag:media-force-nsfw",
               "mrf_tag:media-strip",
               "mrf_tag:sandbox",
               "unchanged",
               "x",
               "y"
             ] == response
    end
  end

  describe "PUT /api/pleroma/admin/users/tag" do
    setup %{conn: conn} do
      user1 = insert(:user, %{tags: [build(:tag, name: "x")]})
      user2 = insert(:user, %{tags: [build(:tag, name: "y")]})
      user3 = insert(:user, %{tags: [build(:tag, name: "unchanged")]})

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put(
          "/api/pleroma/admin/users/tag?nicknames[]=#{user1.nickname}&nicknames[]=" <>
            "#{user2.nickname}&tags[]=foo&tags[]=bar"
        )

      %{conn: conn, user1: user1, user2: user2, user3: user3}
    end

    test "it appends specified tags to users with specified nicknames", %{
      conn: conn,
      admin: admin,
      user1: user1,
      user2: user2
    } do
      assert empty_json_response(conn)
      {:ok, tags} = Repo.get_assoc(User.get_cached_by_id(user1.id), :tags)
      assert Enum.map(tags, & &1.name) == ["x", "foo", "bar"]
      {:ok, tags} = Repo.get_assoc(User.get_cached_by_id(user2.id), :tags)
      assert Enum.map(tags, & &1.name) == ["y", "foo", "bar"]

      log_entry = Repo.one(ModerationLog)

      users =
        [user1.nickname, user2.nickname]
        |> Enum.map(&"@#{&1}")
        |> Enum.join(", ")

      tags = ["foo", "bar"] |> Enum.join(", ")

      assert ModerationLog.get_log_entry_message(log_entry) ==
               "@#{admin.nickname} added tags: #{tags} to users: #{users}"
    end

    test "it does not modify tags of not specified users", %{conn: conn, user3: user3} do
      assert empty_json_response(conn)
      {:ok, tags} = Repo.get_assoc(User.get_cached_by_id(user3.id), :tags)
      assert Enum.map(tags, & &1.name) == ["unchanged"]
    end
  end

  describe "DELETE /api/pleroma/admin/users/tag" do
    setup %{conn: conn} do
      user1 = insert(:user, %{tags: [build(:tag, name: "x")]})
      user2 = insert(:user, %{tags: [build(:tag, name: "y"), build(:tag, name: "z")]})
      user3 = insert(:user, %{tags: [build(:tag, name: "unchanged")]})

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> delete(
          "/api/pleroma/admin/users/tag?nicknames[]=#{user1.nickname}&nicknames[]=" <>
            "#{user2.nickname}&tags[]=x&tags[]=z"
        )

      %{conn: conn, user1: user1, user2: user2, user3: user3}
    end

    test "it removes specified tags from users with specified nicknames", %{
      conn: conn,
      admin: admin,
      user1: user1,
      user2: user2
    } do
      assert empty_json_response(conn)
      {:ok, tags} = Repo.get_assoc(User.get_cached_by_id(user1.id), :tags)
      assert tags == []
      {:ok, tags} = Repo.get_assoc(User.get_cached_by_id(user2.id), :tags)
      assert Enum.map(tags, & &1.name) == ["y"]

      log_entry = Repo.one(ModerationLog)

      users =
        [user1.nickname, user2.nickname]
        |> Enum.map(&"@#{&1}")
        |> Enum.join(", ")

      tags = ["x", "z"] |> Enum.join(", ")

      assert ModerationLog.get_log_entry_message(log_entry) ==
               "@#{admin.nickname} removed tags: #{tags} from users: #{users}"
    end

    test "it does not modify tags of not specified users", %{conn: conn, user3: user3} do
      assert empty_json_response(conn)
      {:ok, tags} = Repo.get_assoc(User.get_cached_by_id(user3.id), :tags)
      assert Enum.map(tags, & &1.name) == ["unchanged"]
    end
  end
end
