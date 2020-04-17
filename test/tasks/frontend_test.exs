# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.FrontendTest do
  use ExUnit.Case
  use Pleroma.Tests.Helpers

  import Tesla.Mock, only: [mock_global: 1, json: 1]

  @bundle_zip_path Path.absname("test/fixtures/tesla_mock/fe-bundle.zip")

  @dir "test/tmp/instance_static"

  setup_all do
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
    end)

    :ok
  end

  setup do
    mock_global(fn
      %{method: :get, url: "https://git.pleroma.social/api/v4/projects/" <> rest} ->
        case String.ends_with?(rest, "repository/branches") do
          true ->
            "test/fixtures/tesla_mock/gitlab-api-pleroma-fe-branches.json"

          false ->
            "test/fixtures/tesla_mock/gitlab-api-pleroma-fe-releases.json"
        end
        |> Path.absname()
        |> File.read!()
        |> Jason.decode!()
        |> json()

      %{method: :get, url: _download_url} ->
        %Tesla.Env{status: 200, body: File.read!(@bundle_zip_path)}
    end)

    File.mkdir_p!(@dir)
    on_exit(fn -> File.rm_rf(@dir) end)

    clear_config([:instance, :static_dir], @dir)

    :ok
  end

  test "installations" do
    frontends = ~w(pleroma kenoma mastodon admin)
    refs = ~w(develop stable 1.2.3)

    Enum.each(frontends, fn frontend ->
      Enum.each(refs, fn ref ->
        Mix.Tasks.Pleroma.Frontend.run([
          "install",
          frontend,
          "--ref",
          ref
        ])

        assert File.exists?(Path.join([@dir, "frontends/#{frontend}/#{ref}/index.html"]))
      end)
    end)
  end
end
