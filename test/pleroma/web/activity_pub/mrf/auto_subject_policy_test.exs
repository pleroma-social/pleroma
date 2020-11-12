defmodule Pleroma.Web.ActivityPub.MRF.AutoSubjectPolicyTest do
  use Pleroma.DataCase

  import Pleroma.Factory

  alias Pleroma.Web.ActivityPub.MRF.AutoSubjectPolicy

  describe "filter/1" do
    setup do
      user = insert(:user)
      [user: user]
    end

    test "pattern as string", %{user: user} do
      clear_config([:mrf_auto_subject, :match], [{"yes", "no"}])

      assert {:ok, %{"object" => %{"content" => "yes & no", "summary" => "no"}}} =
               AutoSubjectPolicy.filter(%{
                 "type" => "Create",
                 "actor" => user.ap_id,
                 "object" => %{"content" => "yes & no", "summary" => ""}
               })
    end

    test "pattern as list", %{user: user} do
      clear_config([:mrf_auto_subject, :match], [{["yes", "yep"], "no"}])

      assert {:ok, %{"object" => %{"content" => "yes & no & yep", "summary" => "no"}}} =
               AutoSubjectPolicy.filter(%{
                 "type" => "Create",
                 "actor" => user.ap_id,
                 "object" => %{"content" => "yes & no & yep"}
               })
    end

    test "multiple matches", %{user: user} do
      clear_config([:mrf_auto_subject, :match], [{["yes", "yep"], "no"}, {"cat", "dog"}])

      assert {:ok, %{"object" => %{"content" => "yes & no & cat", "summary" => "dog, no"}}} =
               AutoSubjectPolicy.filter(%{
                 "type" => "Create",
                 "actor" => user.ap_id,
                 "object" => %{"content" => "yes & no & cat"}
               })
    end

    test "with no match", %{user: user} do
      clear_config([:mrf_auto_subject, :match], [{"yes", "no"}])

      assert {:ok, %{"object" => %{"content" => "only no", "summary" => ""}}} =
               AutoSubjectPolicy.filter(%{
                 "type" => "Create",
                 "actor" => user.ap_id,
                 "object" => %{"content" => "only no", "summary" => ""}
               })
    end

    test "user is not local" do
      user = insert(:user, local: false)
      clear_config([:mrf_auto_subject, :match], [{"yes", "no"}])

      assert {:ok, %{"object" => %{"content" => "yes & no", "summary" => ""}}} =
               AutoSubjectPolicy.filter(%{
                 "type" => "Create",
                 "actor" => user.ap_id,
                 "object" => %{"content" => "yes & no", "summary" => ""}
               })
    end

    test "object contains summary", %{user: user} do
      clear_config([:mrf_auto_subject, :match], [{"yes", "no"}])

      assert {:ok, %{"object" => %{"content" => "yes & no", "summary" => "subject"}}} =
               AutoSubjectPolicy.filter(%{
                 "type" => "Create",
                 "actor" => user.ap_id,
                 "object" => %{"content" => "yes & no", "summary" => "subject"}
               })
    end
  end

  test "describe/0" do
    clear_config([:mrf_auto_subject, :match], [{"yes", "no"}])

    assert AutoSubjectPolicy.describe() ==
             {:ok,
              %{
                mrf_auto_subject: %{
                  match: [{"yes", "no"}]
                }
              }}
  end

  test "config_description/0" do
    assert %{key: _, related_policy: _, label: _, description: _} =
             AutoSubjectPolicy.config_description()
  end
end
