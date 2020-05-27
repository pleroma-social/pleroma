# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.AttachmentsCleanupWorker do
  import Ecto.Query

  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.Web.MediaProxy

  use Pleroma.Workers.WorkerHelper, queue: "attachments_cleanup"

  @impl Oban.Worker
  def perform(
        %{
          "op" => "cleanup_attachments",
          "object" => %{"data" => %{"attachment" => [_ | _] = attachments, "actor" => actor}}
        },
        _job
      ) do
    hrefs =
      Enum.flat_map(attachments, fn attachment ->
        Enum.map(attachment["url"], & &1["href"])
      end)

    uploader = Pleroma.Config.get([Pleroma.Upload, :uploader])

    prefix =
      case Pleroma.Config.get([Pleroma.Upload, :base_url]) do
        nil -> "media"
        _ -> ""
      end

    base_url =
      String.trim_trailing(
        Pleroma.Config.get([Pleroma.Upload, :base_url], Pleroma.Web.base_url()),
        "/"
      )

    # find all objects for copies of the attachments, name and actor doesn't matter here
    {object_ids, attachment_urls} =
      hrefs
      |> fetch_objects
      |> prepare_objects(actor, Enum.map(attachments, & &1["name"]))
      |> Enum.reduce({[], []}, fn {href, %{id: id, count: count}}, {ids, hrefs} ->
        with 1 <- count do
          {ids ++ [id], hrefs ++ [href]}
        else
          _ -> {ids ++ [id], hrefs}
        end
      end)

    lock_attachments(MediaProxy.Invalidation.enabled(), attachment_urls)

    Enum.each(attachment_urls, fn href ->
      href
      |> String.trim_leading("#{base_url}/#{prefix}")
      |> uploader.delete_file()
    end)

    Repo.delete_all(from(o in Object, where: o.id in ^object_ids))

    cache_purge(MediaProxy.Invalidation.enabled(), attachment_urls)

    {:ok, :success}
  end

  def perform(%{"op" => "cleanup_attachments", "object" => _object}, _job), do: {:ok, :skip}

  defp cache_purge(true, attachment_urls) do
    MediaProxy.Invalidation.purge(attachment_urls)
  end

  defp cache_purge(_, _), do: :ok

  defp lock_attachments(true, attachment_urls) do
    MediaProxy.put_in_deleted_urls(attachment_urls)
  end

  defp lock_attachments(_, _), do: :ok

  # we should delete 1 object for any given attachment, but don't delete
  # files if there are more than 1 object for it
  defp prepare_objects(objects, actor, names) do
    objects
    |> Enum.reduce(%{}, fn %{
                             id: id,
                             data: %{
                               "url" => [%{"href" => href}],
                               "actor" => obj_actor,
                               "name" => name
                             }
                           },
                           acc ->
      Map.update(acc, href, %{id: id, count: 1}, fn val ->
        case obj_actor == actor and name in names do
          true ->
            # set id of the actor's object that will be deleted
            %{val | id: id, count: val.count + 1}

          false ->
            # another actor's object, just increase count to not delete file
            %{val | count: val.count + 1}
        end
      end)
    end)
  end

  defp fetch_objects(hrefs) do
    from(o in Object,
      where:
        fragment(
          "to_jsonb(array(select jsonb_array_elements((?)#>'{url}') ->> 'href' where jsonb_typeof((?)#>'{url}') = 'array'))::jsonb \\?| (?)",
          o.data,
          o.data,
          ^hrefs
        )
    )
    # The query above can be time consumptive on large instances until we
    # refactor how uploads are stored
    |> Repo.all(timeout: :infinity)
  end
end
