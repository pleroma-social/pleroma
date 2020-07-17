# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.Frontend do
  @doc """
  Scenario 1:
  - clone repo to /frontends/fe/_src_tmp
  - build fe
  - move built files into /frontends/fe
  - remove frontends/fe/_src_tmp

  Scenario 2:
  - download bundle from CI to /frontends/fe/_src_tmp
  - move build files
  - remove tmp

  Scenario 3:
  - move built files from _path to /frontends/fe

  Pleroma:
    /dist
  Kenoma:
    /build
  Fedi:
    /dist
  Admin:
    /dist
  Mastodon
    /public
  """
  use Mix.Task

  import Mix.Pleroma

  # alias Pleroma.Config

  @shortdoc "Manages bundled Pleroma frontends"
  @moduledoc File.read!("docs/administration/CLI_tasks/frontend.md")

  @frontends %{
    "admin" => %{"project" => "pleroma/admin-fe"},
    "kenoma" => %{"project" => "lambadalambda/kenoma"},
    "mastodon" => %{"project" => "pleroma/mastofe"},
    "pleroma" => %{"project" => "pleroma/pleroma-fe"},
    "fedi" => %{"project" => "dockyard/fedi-fe"}
  }
  @known_frontends Map.keys(@frontends)

  @ref_local "__local__"

  def run(["install", "none" | _args]) do
    shell_info("Skipping frontend installation because none was requested")
  end

  def run(["install", unknown_fe | _args]) when unknown_fe not in @known_frontends do
    shell_error(
      "Frontend \"#{unknown_fe}\" is not known. Known frontends are: #{
        Enum.join(@known_frontends, ", ")
      }"
    )
  end

  def run(["install", frontend | args]) do
    log_level = Logger.level()
    Logger.configure(level: :warn)
    {:ok, _} = Application.ensure_all_started(:pleroma)

    {options, [], []} =
      OptionParser.parse(
        args,
        strict: [
          ref: :string,
          path: :string,
          develop: :boolean
        ]
      )

    path = options[:path]
    ref = local_path_frontend_ref(path)

    dest =
      Path.join([
        Pleroma.Config.get!([:instance, :static_dir]),
        "frontends",
        frontend,
        ref
      ])

    shell_info("Installing frontend #{frontend} (#{ref}) from local path")

    install_bundle(frontend, path, dest)
    shell_info("Frontend #{frontend} (#{ref}) installed to #{dest}")

    Logger.configure(level: log_level)
  end

  defp local_path_frontend_ref(path) do
    path
    |> Path.join("package.json")
    |> File.read()
    |> case do
      {:ok, bin} ->
        bin
        |> Jason.decode!()
        |> Map.get("version", @ref_local)

      _ ->
        @ref_local
    end
  end

  defp post_install("mastodon", path) do
    File.rename!("#{path}/assets/sw.js", "#{path}/sw.js")

    {:ok, files} = File.ls(path)

    Enum.each(files, fn file ->
      with false <- file in ~w(packs sw.js) do
        [path, file]
        |> Path.join()
        |> File.rm_rf!()
      end
    end)
  end

  defp post_install(_frontend, _path) do
    :ok
  end

  defp install_bundle(frontend, source, dest) do
    from =
      case frontend do
        "mastodon" ->
          "public"

        "kenoma" ->
          "build"

        _ ->
          "dist"
      end

    File.mkdir_p!(dest)
    File.cp_r!(Path.join([source, from]), dest)
    post_install(frontend, dest)
    :ok
  end
end
