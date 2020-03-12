# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.Frontend do
  use Mix.Task
  import Mix.Pleroma

  @shortdoc "Manages the Pleroma frontends"
  @moduledoc File.read!("docs/administration/CLI_tasks/frontend.md")

  def run(["download" | rest]) do
    {options, [], []} =
      OptionParser.parse(
        rest,
        strict: [
          reference: :string
        ],
        aliases: [r: :reference]
      )

    reference = options[:reference] || "master"

    shell_info("Downloading reference #{reference}")

    url =
      "https://git.pleroma.social/pleroma/pleroma-fe/-/jobs/artifacts/#{reference}/download?job=build"

    sd =
      Pleroma.Config.get([:instance, :frontends_dir], "instance/frontends")
      |> Path.join("pleroma-fe")
      |> Path.expand()

    adapter =
      if Pleroma.Config.get(:env) == :test do
        Tesla.Mock
      else
        Tesla.Adapter.Httpc
      end

    client = Tesla.client([Tesla.Middleware.FollowRedirects], adapter)

    with {_, {:ok, %{status: 200, body: body}}} <- {:fetch, Tesla.get(client, url)},
         {_, {:ok, results}} <- {:unzip, :zip.unzip(body, [:memory])},
         shell_info("Cleaning #{sd}"),
         {_, {:ok, _}} <- {:clean_up, File.rm_rf(sd)} do
      shell_info("Writing to #{sd}")

      results
      |> Enum.each(fn {path, contents} ->
        path = String.replace(to_string(path), ~r/^dist/, "")
        path = Path.join(sd, path)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, contents)
      end)

      shell_info("Successfully downloaded and unpacked the frontend")
    else
      {error, _} -> shell_error("Step failed: #{error}")
    end
  end
end
