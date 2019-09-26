defmodule Pleroma.Web.ActivityPub.UserViewTest do
  use Pleroma.DataCase
  import Pleroma.Factory

  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.UserView
  alias Pleroma.Web.CommonAPI

  test "Renders a user, including the public key" do
    user = insert(:user)
    {:ok, user} = User.ensure_keys_present(user)

    result = UserView.render("user.json", %{user: user})

    assert result["id"] == user.ap_id
    assert result["preferredUsername"] == user.nickname

    assert String.contains?(result["publicKey"]["publicKeyPem"], "BEGIN PUBLIC KEY")
  end

  test "Does not add an avatar image if the user hasn't set one" do
    user = insert(:user)
    {:ok, user} = User.ensure_keys_present(user)

    result = UserView.render("user.json", %{user: user})
    refute result["icon"]
    refute result["image"]

    user =
      insert(:user,
        avatar: %{"url" => [%{"href" => "https://someurl"}]},
        info: %{
          banner: %{"url" => [%{"href" => "https://somebanner"}]}
        }
      )

    {:ok, user} = User.ensure_keys_present(user)

    result = UserView.render("user.json", %{user: user})
    assert result["icon"]["url"] == "https://someurl"
    assert result["image"]["url"] == "https://somebanner"
  end

  describe "endpoints" do
    test "local users have a usable endpoints structure" do
      user = insert(:user)
      {:ok, user} = User.ensure_keys_present(user)

      result = UserView.render("user.json", %{user: user})

      assert result["id"] == user.ap_id

      %{
        "sharedInbox" => _,
        "oauthAuthorizationEndpoint" => _,
        "oauthRegistrationEndpoint" => _,
        "oauthTokenEndpoint" => _
      } = result["endpoints"]
    end

    test "remote users have an empty endpoints structure" do
      user = insert(:user, local: false)
      {:ok, user} = User.ensure_keys_present(user)

      result = UserView.render("user.json", %{user: user})

      assert result["id"] == user.ap_id
      assert result["endpoints"] == %{}
    end

    test "instance users do not expose oAuth endpoints" do
      user = insert(:user, nickname: nil, local: true)
      {:ok, user} = User.ensure_keys_present(user)

      result = UserView.render("user.json", %{user: user})

      refute result["endpoints"]["oauthAuthorizationEndpoint"]
      refute result["endpoints"]["oauthRegistrationEndpoint"]
      refute result["endpoints"]["oauthTokenEndpoint"]
    end
  end

  test "activity collection page aginates correctly" do
    user = insert(:user)

    posts =
      for i <- 0..25 do
        {:ok, activity} = CommonAPI.post(user, %{"status" => "post #{i}"})
        activity
      end

    # outbox sorts chronologically, newest first, with ten per page
    posts = Enum.reverse(posts)

    %{"next" => next_url} =
      UserView.render("activity_collection_page.json", %{
        iri: "#{user.ap_id}/outbox",
        activities: Enum.take(posts, 10)
      })

    next_id = Enum.at(posts, 9).id
    assert next_url =~ next_id

    %{"next" => next_url} =
      UserView.render("activity_collection_page.json", %{
        iri: "#{user.ap_id}/outbox",
        activities: Enum.take(Enum.drop(posts, 10), 10)
      })

    next_id = Enum.at(posts, 19).id
    assert next_url =~ next_id
  end
end
