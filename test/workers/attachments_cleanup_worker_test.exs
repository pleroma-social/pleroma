# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.AttachmentsCleanupWorkerTest do
  use Pleroma.DataCase

  alias Pleroma.Config
  alias Pleroma.Web.MediaProxy
  alias Pleroma.Workers.AttachmentsCleanupWorker

  import Mock
  import Pleroma.Factory

  describe "delete attachments" do
    setup do: clear_config([Pleroma.Upload])
    setup do: clear_config([:instance, :cleanup_attachments])
    setup do: clear_config([:media_proxy])

    test "deletes attachment objects and run purge cache" do
      Config.put([Pleroma.Upload, :uploader], Pleroma.Uploaders.Local)
      Config.put([:instance, :cleanup_attachments], true)
      Config.put([:media_proxy, :invalidation, :enabled], true)
      Config.put([:media_proxy, :invalidation, :provider], MediaProxy.Invalidation.Mock)

      file = %Plug.Upload{
        content_type: "image/jpg",
        path: Path.absname("test/fixtures/image.jpg"),
        filename: "an_image.jpg"
      }

      user = insert(:user)

      {:ok, %Pleroma.Object{} = attachment} =
        Pleroma.Web.ActivityPub.ActivityPub.upload(file, actor: user.ap_id)

      remote_url = "http://example.com/media/d6661b98ae72e39.jpg"
      %{data: %{"url" => [%{"href" => local_url}]}} = attachment

      note =
        insert(:note, %{
          user: user,
          data: %{
            "attachment" => [
              attachment.data,
              %{
                "actor" => user.ap_id,
                "name" => "v_image.jpg",
                "type" => "Document",
                "url" => [
                  %{"href" => remote_url, "mediaType" => "image/jpeg", "type" => "Link"}
                ]
              }
            ]
          }
        })

      uploads_dir = Pleroma.Config.get!([Pleroma.Uploaders.Local, :uploads])

      path = local_url |> Path.dirname() |> Path.basename()

      assert {:ok, ["an_image.jpg"]} == File.ls("#{uploads_dir}/#{path}")

      with_mocks [
        {MediaProxy.Invalidation, [:passthrough],
         [purge: fn [^local_url, ^remote_url] -> :ok end]}
      ] do
        assert AttachmentsCleanupWorker.perform(
                 %{"op" => "cleanup_attachments", "object" => %{"data" => note.data}},
                 :job
               ) == {:ok, :success}
      end

      refute Pleroma.Object.get_by_id(attachment.id)
      assert {:ok, []} == File.ls("#{uploads_dir}/#{path}")

      refute Pleroma.Web.MediaProxy.in_deleted_urls(local_url)
      assert Pleroma.Web.MediaProxy.in_deleted_urls(remote_url)
    end

    test "skip execution" do
      assert AttachmentsCleanupWorker.perform(
               %{
                 "op" => "cleanup_attachments",
                 "object" => %{}
               },
               :job
             ) == {:ok, :skip}
    end
  end
end
