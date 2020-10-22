# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.TagTest do
  use Pleroma.DataCase

  import Pleroma.Factory

  alias Pleroma.Tag

  describe "upsert/1" do
    test "create new normalize tag" do
      Tag.upsert("  verify   \n")

      assert [tag] = Pleroma.Repo.all(Tag)
      assert tag.name == "verify"
    end

    test "create new tag" do
      Tag.upsert("verify")

      assert [tag] = Pleroma.Repo.all(Tag)
      assert tag.name == "verify"
    end

    test "do nothing when tag exists" do
      insert(:tag, name: "verify")
      Tag.upsert("verify")

      assert [tag] = Pleroma.Repo.all(Tag)
      assert tag.name == "verify"
    end
  end

  describe "upsert_tags/1" do
    test "create new normalize tags" do
      Tag.upsert_tags(["  verify   \n", "bot", "unconfirmed   "])

      assert tags = Pleroma.Repo.all(Tag)
      assert Enum.sort(Enum.map(tags, & &1.name)) == ["bot", "unconfirmed", "verify"]
    end

    test "do nothing when tag exists" do
      insert(:tag, name: "verify")

      Tag.upsert_tags(["  verify   \n", "bot", "unconfirmed   "])

      assert tags = Pleroma.Repo.all(Tag)
      assert Enum.sort(Enum.map(tags, & &1.name)) == ["bot", "unconfirmed", "verify"]
    end
  end

  describe "get_tag_ids/1" do
    test "returns tags by name" do
      verify_tag = insert(:tag, name: "verify")
      bot_tag = insert(:tag, name: "bot")
      unconfirmed_tag = insert(:tag, name: "unconfirmed")

      tag_ids = Tag.get_tag_ids(["bot", "verify"])
      assert verify_tag.id in tag_ids
      assert bot_tag.id in tag_ids
      refute unconfirmed_tag.id in tag_ids
    end
  end

  describe "list_tags/0" do
    test "returns all users tags + mrf tags" do
      insert(:tag, name: "verify")
      insert(:tag, name: "bot")
      insert(:tag, name: "unconfirmed")
      insert(:tag, name: "mrf_tag:media-strip")

      assert Enum.sort(Tag.list_tags()) == [
               "bot",
               "mrf_tag:disable-any-subscription",
               "mrf_tag:disable-remote-subscription",
               "mrf_tag:force-unlisted",
               "mrf_tag:media-force-nsfw",
               "mrf_tag:media-strip",
               "mrf_tag:sandbox",
               "unconfirmed",
               "verify"
             ]
    end
  end

  describe "normalize_tags/1" do
    test "returns normalize tags" do
      assert ["verify", "bot"] == Tag.normalize_tags(["  verify \n", "\n  bot  "])
      assert ["verify"] == Tag.normalize_tags("  verify \n")
    end
  end
end
