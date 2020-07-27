# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.Frontend do
  use Mix.Task

  import Mix.Pleroma

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
  @ref_develop "__develop__"
  @ref_stable "__stable__"

  @pleroma_gitlab_host "git.pleroma.social"

  def run(["install", "none" | _args]) do
    shell_info("Skipping frontend installation because none was requested")
    "none"
  end

  def run(["install", "all"]) do
    {:ok, _} = Application.ensure_all_started(:pleroma)

    configs = Pleroma.Config.get(:frontends, %{})

    with config <- configs[:primary],
         frontend <- config["name"],
         ref when ref != "none" <- config["ref"] do
      run(["install", frontend, "--ref", ref])
    end

    with config <- configs[:mastodon],
         ref when ref != "none" <- config["ref"] do
      run(["install", "mastodon", "--ref", ref])
    end

    with config <- configs[:admin],
         ref when ref != "none" <- config["ref"] do
      run(["install", "admin", "--ref", ref])
    end
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
          develop: :boolean,
          static_dir: :string
        ]
      )

    instance_static_dir =
      with nil <- options[:static_dir] do
        Pleroma.Config.get!([:instance, :static_dir])
      end

    ref =
      case options[:path] do
        nil ->
          ref0 =
            cond do
              options[:ref] -> options[:ref]
              options[:develop] -> @ref_develop
              true -> @ref_stable
            end

          web_frontend_ref(frontend, ref0)

        path ->
          local_path_frontend_ref(path)
      end

    dest =
      Path.join([
        instance_static_dir,
        "frontends",
        frontend,
        ref
      ])

    fe_label = "#{frontend} (#{ref})"

    from =
      with nil <- options[:path] do
        Pleroma.Utils.command_required!("yarn")

        url = archive_url(frontend, ref)

        tmp_dir = Path.join(dest, "tmp/src")

        shell_info("Downloading #{fe_label} to #{tmp_dir}")
        :ok = download_frontend(url, tmp_dir)

        shell_info("Building #{fe_label} (this will take some time)")
        :ok = build_frontend(frontend, tmp_dir)
        tmp_dir
      end

    shell_info("Installing #{fe_label} to #{dest}")

    :ok = install_frontend(frontend, from, dest)

    shell_info("Frontend #{fe_label} installed to #{dest}")
    Logger.configure(level: log_level)
    ref
  end

  defp download_frontend(url, dest) do
    with {:ok, %{status: 200, body: zip_body}} <-
           Pleroma.HTTP.get(url, [], timeout: 120_000, recv_timeout: 120_000),
         {:ok, unzipped} <- :zip.unzip(zip_body, [:memory]) do
      File.rm_rf!(dest)
      File.mkdir_p!(dest)

      Enum.each(unzipped, fn {filename, data} ->
        [_root | paths] = Path.split(filename)
        path = Enum.join(paths, "/")
        new_file_path = Path.join(dest, path)

        new_file_path
        |> Path.dirname()
        |> File.mkdir_p!()

        File.write!(new_file_path, data)
      end)
    else
      {:ok, %{status: 404}} ->
        {:error, "Bundle not found"}

      false ->
        {:error, "Zip archive must contain \"dist\" folder"}

      error ->
        {:error, error}
    end
  end

  defp build_frontend("admin", path) do
    yarn = Pleroma.Config.get(:yarn, "yarn")
    {_out, 0} = System.cmd(yarn, [], cd: path)
    {_out, 0} = System.cmd(yarn, ["build:prod"], cd: path)
    :ok
  end

  defp build_frontend(_frontend, path) do
    yarn = Pleroma.Config.get(:yarn, "yarn")
    {_out, 0} = System.cmd(yarn, [], cd: path)
    {_out, 0} = System.cmd(yarn, ["build"], cd: path)
    :ok
  end

  defp web_frontend_ref(frontend, @ref_develop) do
    url = project_url(frontend) <> "/repository/branches"

    {:ok, %{status: 200, body: body}} =
      Pleroma.HTTP.get(url, [], timeout: 120_000, recv_timeout: 120_000)

    json = Jason.decode!(body)

    %{"commit" => %{"short_id" => last_commit_ref}} = Enum.find(json, & &1["default"])

    last_commit_ref
  end

  # fallback to develop version if compatible stable ref is not defined in
  # mix.exs for the given frontend
  defp web_frontend_ref(frontend, @ref_stable) do
    case Map.get(Pleroma.Application.frontends(), frontend) do
      nil ->
        web_frontend_ref(frontend, @ref_develop)

      ref ->
        ref
    end
  end

  defp web_frontend_ref(_frontend, ref), do: ref

  defp project_url(frontend),
    do:
      "https://#{@pleroma_gitlab_host}/api/v4/projects/#{
        URI.encode_www_form(@frontends[frontend]["project"])
      }"

  defp archive_url(frontend, ref),
    do: "https://#{@pleroma_gitlab_host}/#{@frontends[frontend]["project"]}/-/archive/#{ref}.zip"

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

  defp install_frontend(frontend, source, dest) do
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
  end
end
