# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.MediaControllerTest do
  use Pleroma.Web.ConnCase

  alias Pleroma.Object
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub

  describe "Upload media" do
    setup do: oauth_access(["write:media"])

    setup do
      image = %Plug.Upload{
        content_type: "image/jpeg",
        path: Path.absname("test/fixtures/image.jpg"),
        filename: "an_image.jpg"
      }

      [image: image]
    end

    setup do: clear_config([:media_proxy])
    setup do: clear_config([Pleroma.Upload])

    test "/api/v1/media", %{conn: conn, image: image} do
      desc = "Description of the image"
      filename = "look at this.jpg"

      media =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v1/media", %{"file" => image, "description" => desc, "filename" => filename})
        |> json_response_and_validate_schema(:ok)

      assert media["type"] == "image"
      assert media["description"] == desc
      assert media["pleroma"]["filename"] == filename
      assert media["id"]

      object = Object.get_by_id(media["id"])
      assert object.data["actor"] == User.ap_id(conn.assigns[:user])
    end

    test "/api/v2/media", %{conn: conn, user: user, image: image} do
      desc = "Description of the image"
      filename = "look at this.jpg"

      response =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v2/media", %{"file" => image, "description" => desc, "filename" => filename})
        |> json_response_and_validate_schema(202)

      assert media_id = response["id"]

      %{conn: conn} = oauth_access(["read:media"], user: user)

      media =
        conn
        |> get("/api/v1/media/#{media_id}")
        |> json_response_and_validate_schema(200)

      assert media["type"] == "image"
      assert media["description"] == desc
      assert media["pleroma"]["filename"] == filename
      assert media["id"]

      object = Object.get_by_id(media["id"])
      assert object.data["actor"] == user.ap_id
    end

    test "returns error when description is too long", %{conn: conn, image: image} do
      clear_config([:instance, :description_limit], 2)

      response =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v1/media", %{"file" => image, "description" => "test-media"})
        |> json_response(400)

      assert response["error"] == "description_too_long"
    end

    @tag capture_log: true
    test "returns error when custom filename has different extension than original one", %{
      conn: conn,
      image: image
    } do
      response =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v1/media", %{"file" => image, "filename" => "wrong.gif"})
        |> json_response(400)

      assert response["error"] == "invalid_filename_extension"
    end
  end

  describe "Update media" do
    setup do: oauth_access(["write:media"])

    setup %{user: actor} do
      file = %Plug.Upload{
        content_type: "image/jpeg",
        path: Path.absname("test/fixtures/image.jpg"),
        filename: "an_image.jpg"
      }

      {:ok, %Object{} = object} =
        ActivityPub.upload(
          file,
          actor: User.ap_id(actor),
          description: "test-m",
          filename: "test_image.jpg"
        )

      [object: object]
    end

    test "/api/v1/media/:id update description", %{conn: conn, object: object} do
      new_description = "test-media"

      media =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> put("/api/v1/media/#{object.id}", %{"description" => new_description})
        |> json_response_and_validate_schema(:ok)

      assert media["description"] == new_description
      assert refresh_record(object).data["name"] == new_description
    end

    test "/api/v1/media/:id update filename", %{conn: conn, object: object} do
      new_filename = "media.jpg"

      media =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> put("/api/v1/media/#{object.id}", %{"filename" => new_filename})
        |> json_response_and_validate_schema(:ok)

      assert media["pleroma"]["filename"] == new_filename
      assert refresh_record(object).data["filename"] == new_filename
    end

    test "/api/v1/media/:id update description and filename", %{conn: conn, object: object} do
      new_description = "test-media"
      new_filename = "media.jpg"

      media =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> put("/api/v1/media/#{object.id}", %{
          "description" => new_description,
          "filename" => new_filename,
          "foo" => "bar"
        })
        |> json_response_and_validate_schema(:ok)

      assert media["description"] == new_description
      assert media["pleroma"]["filename"] == new_filename
      assert refresh_record(object).data["name"] == new_description
      assert refresh_record(object).data["filename"] == new_filename
    end

    test "/api/v1/media/:id filename with a wrong extension", %{conn: conn, object: object} do
      new_filename = "media.exe"

      response =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> put("/api/v1/media/#{object.id}", %{"filename" => new_filename})
        |> json_response(400)

      assert response["error"] == "invalid_filename_extension"
    end
  end

  describe "Get media by id (/api/v1/media/:id)" do
    setup do: oauth_access(["read:media"])

    setup %{user: actor} do
      file = %Plug.Upload{
        content_type: "image/jpeg",
        path: Path.absname("test/fixtures/image.jpg"),
        filename: "an_image.jpg"
      }

      {:ok, %Object{} = object} =
        ActivityPub.upload(
          file,
          actor: User.ap_id(actor),
          description: "test-media"
        )

      [object: object]
    end

    test "it returns media object when requested by owner", %{conn: conn, object: object} do
      media =
        conn
        |> get("/api/v1/media/#{object.id}")
        |> json_response_and_validate_schema(:ok)

      assert media["description"] == "test-media"
      assert media["type"] == "image"
      assert media["id"]
    end

    test "it returns 403 if media object requested by non-owner", %{object: object, user: user} do
      %{conn: conn, user: other_user} = oauth_access(["read:media"])

      assert object.data["actor"] == user.ap_id
      refute user.id == other_user.id

      conn
      |> get("/api/v1/media/#{object.id}")
      |> json_response(403)
    end
  end
end
