defmodule Pleroma.Web.ActivityPub.MRF.AutoSubjectPolicyTest do
  use Pleroma.DataCase

  import Pleroma.Factory

  alias Pleroma.Web.ActivityPub.MRF.AutoSubjectPolicy

  describe "filter/1" do
    setup do
      user = insert(:user)
      [user: user]
    end

    test "pattern as string, matches case insensitive", %{user: user} do
      clear_config([:mrf_auto_subject, :match], [{"senate", "uspol"}])

      assert {:ok,
              %{"object" => %{"content" => "The Senate is now in recess.", "summary" => "uspol"}}} =
               AutoSubjectPolicy.filter(%{
                 "type" => "Create",
                 "actor" => user.ap_id,
                 "object" => %{"content" => "The Senate is now in recess.", "summary" => ""}
               })
    end

    test "pattern as list", %{user: user} do
      clear_config([:mrf_auto_subject, :match], [{["dinner", "sandwich"], "food"}])

      assert {:ok,
              %{
                "object" => %{
                  "content" => "I decided to eat leftovers for dinner again.",
                  "summary" => "food"
                }
              }} =
               AutoSubjectPolicy.filter(%{
                 "type" => "Create",
                 "actor" => user.ap_id,
                 "object" => %{"content" => "I decided to eat leftovers for dinner again."}
               })
    end

    test "multiple matches and punctuation trimming", %{user: user} do
      clear_config([:mrf_auto_subject, :match], [{["dog", "cat"], "pets"}, {"Torvalds", "Linux"}])

      assert {:ok,
              %{
                "object" => %{
                  "content" => "A long time ago I named my dog after Linus Torvalds.",
                  "summary" => "Linux, pets"
                }
              }} =
               AutoSubjectPolicy.filter(%{
                 "type" => "Create",
                 "actor" => user.ap_id,
                 "object" => %{
                   "content" => "A long time ago I named my dog after Linus Torvalds."
                 }
               })
    end

    test "with no match", %{user: user} do
      clear_config([:mrf_auto_subject, :match], [{"puppy", "pets"}])

      assert {:ok, %{"object" => %{"content" => "I have a kitten", "summary" => ""}}} =
               AutoSubjectPolicy.filter(%{
                 "type" => "Create",
                 "actor" => user.ap_id,
                 "object" => %{"content" => "I have a kitten", "summary" => ""}
               })
    end

    test "user is not local" do
      user = insert(:user, local: false)
      clear_config([:mrf_auto_subject, :match], [{"puppy", "pets"}])

      assert {:ok, %{"object" => %{"content" => "We just got a puppy", "summary" => ""}}} =
               AutoSubjectPolicy.filter(%{
                 "type" => "Create",
                 "actor" => user.ap_id,
                 "object" => %{"content" => "We just got a puppy", "summary" => ""}
               })
    end

    test "subject is already set", %{user: user} do
      clear_config([:mrf_auto_subject, :match], [{"election", "politics"}])

      assert {:ok,
              %{
                "object" => %{
                  "content" => "If your election lasts more than 4 hours you should see a doctor",
                  "summary" => "uspol, humor"
                }
              }} =
               AutoSubjectPolicy.filter(%{
                 "type" => "Create",
                 "actor" => user.ap_id,
                 "object" => %{
                   "content" =>
                     "If your election lasts more than 4 hours you should see a doctor",
                   "summary" => "uspol, humor"
                 }
               })
    end
  end

  test "describe/0" do
    clear_config([:mrf_auto_subject, :match], [{"dog", "pets"}])

    assert AutoSubjectPolicy.describe() ==
             {:ok,
              %{
                mrf_auto_subject: %{
                  match: [{"dog", "pets"}]
                }
              }}
  end

  test "config_description/0" do
    assert %{key: _, related_policy: _, label: _, description: _} =
             AutoSubjectPolicy.config_description()
  end
end
