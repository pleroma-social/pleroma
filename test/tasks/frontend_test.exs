# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.FrontendTest do
  use ExUnit.Case
  use Pleroma.Tests.Helpers

  import Tesla.Mock, only: [mock_global: 1, json: 1]

  @bundle_zip_path Path.absname("test/fixtures/tesla_mock/fe-bundle.zip")

  @tmp "test/tmp"
  @dir "#{@tmp}/instance_static"

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
        if String.ends_with?(rest, "repository/branches") do
          "test/fixtures/tesla_mock/gitlab-api-pleroma-fe-branches.json"
        else
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

  describe "Installations from local path" do
    test "Frontends with standard dist structure" do
      ~w(pleroma kenoma admin)
      |> Enum.each(fn frontend ->
        path = "test/fixtures/frontends/#{frontend}"
        Mix.Tasks.Pleroma.Frontend.run(~w(install #{frontend} --path #{path}))

        assert File.exists?("#{@dir}/frontends/#{frontend}/42/index.html")
        refute File.exists?("#{@dir}/frontends/#{frontend}/42/package.json")
      end)
    end

    test "Mastodon" do
      path = "test/fixtures/frontends/mastodon"
      Mix.Tasks.Pleroma.Frontend.run(~w(install mastodon --path #{path}))

      assert File.exists?("#{@dir}/frontends/mastodon/__local__/sw.js")
      assert File.exists?("#{@dir}/frontends/mastodon/__local__/packs/locales.js")
      refute File.exists?("#{@dir}/frontends/mastodon/__local__/unused_file")
      refute File.exists?("#{@dir}/frontends/mastodon/__local__/unused_dir")
    end
  end

  describe "Installation from web, pre-built packages" do
    test "develop" do
      Mix.Tasks.Pleroma.Frontend.run([
        "install",
        "pleroma",
        "--develop"
      ])

      assert File.exists?(Path.join([@dir, "frontends/pleroma/d5457c32/index.html"]))
    end

    test "stable" do
      Mix.Tasks.Pleroma.Frontend.run(["install", "pleroma"])

      assert File.exists?(Path.join([@dir, "frontends/pleroma/5d49edc8/index.html"]))
    end

    test "ref" do
      Mix.Tasks.Pleroma.Frontend.run([
        "install",
        "pleroma",
        "--ref",
        "1.2.3"
      ])

      assert File.exists?(Path.join([@dir, "frontends/pleroma/1.2.3/index.html"]))
    end
  end
end
