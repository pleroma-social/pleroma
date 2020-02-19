# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.Frontend do
  use Mix.Task
  alias __MODULE__.Fetcher

  @shortdoc "Manages the Pleroma frontends"
  @moduledoc File.read!("docs/administration/CLI_tasks/frontend.md")

  def run(["download" | rest]) do
    {options, [], []} =
      OptionParser.parse(
        rest,
        strict: [
          reference: :string
        ]
      )

    reference = options[:reference] || "master"

    IO.puts("Downloading reference #{reference}")

    url =
      "https://git.pleroma.social/pleroma/pleroma-fe/-/jobs/artifacts/#{reference}/download?job=build"

    sd = Pleroma.Config.get([:instance, :static_dir]) |> Path.expand()

    with {_, {:ok, %{status: 200, body: body}}} <- {:fetch, Fetcher.get(url)},
         {_, {:ok, results}} <- {:unzip, :zip.unzip(body, [:memory])} do
      IO.puts("Writing to #{sd}")

      results
      |> Enum.each(fn {path, contents} ->
        path = String.replace(to_string(path), ~r/^dist/, "")
        path = Path.join(sd, path)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, contents)
      end)

      IO.puts("Successfully downloaded and unpacked the frontend")
    else
      {error, _} -> IO.puts("Step failed: #{error}")
    end
  end
end

defmodule Mix.Tasks.Pleroma.Frontend.Fetcher do
  use Tesla
  plug(Tesla.Middleware.FollowRedirects)

  adapter(Tesla.Adapter.Httpc)
end
