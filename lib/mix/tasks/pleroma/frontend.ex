# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.Frontend do
  use Mix.Task

  import Mix.Pleroma

  # alias Pleroma.Config

  @shortdoc "Manages bundled Pleroma frontends"
  @moduledoc File.read!("docs/administration/CLI_tasks/frontend.md")

  @pleroma_gitlab_host "git.pleroma.social"
  @frontends %{
    # TODO stable
    "admin" => %{"project" => "pleroma/admin-fe"},
    # TODO
    "kenoma" => %{"project" => "lambadalambda/kenoma"},
    # TODO
    "mastodon" => %{"project" => "pleroma/mastofe"},
    # OK
    "pleroma" => %{"project" => "pleroma/pleroma-fe"}
  }
  @known_frontends Map.keys(@frontends)

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
          ref: :string
        ]
      )

    ref = suggest_ref(options, frontend)

    %{"name" => bundle_name, "url" => bundle_url} =
      get_bundle_meta(ref, @pleroma_gitlab_host, @frontends[frontend]["project"])

    shell_info("Installing frontend #{frontend}, version: #{bundle_name}")

    dest = Path.join([Pleroma.Config.get!([:instance, :static_dir]), "frontends", frontend, ref])

    with :ok <- install_bundle(bundle_url, dest),
         :ok <- post_install_bundle(frontend, dest) do
      shell_info("Installed!")
    else
      {:error, error} ->
        shell_error("Error: #{inspect(error)}")
    end

    Logger.configure(level: log_level)
  end

  defp post_install_bundle("mastodon", path) do
    with :ok <- File.rename("#{path}/public/assets/sw.js", "#{path}/sw.js"),
         :ok <- File.rename("#{path}/public/packs", "#{path}/packs"),
         {:ok, _deleted_files} <- File.rm_rf("#{path}/public") do
      :ok
    else
      error ->
        {:error, error}
    end
  end

  defp post_install_bundle(_fe_name, _path), do: :ok

  defp suggest_ref(options, frontend) do
    case Pleroma.Config.get([:frontends, String.to_atom(frontend)]) do
      nil ->
        primary_fe_config = Pleroma.Config.get([:frontends, :primary])

        if primary_fe_config["name"] == frontend do
          primary_fe_config["ref"]
        else
          nil
        end

      val ->
        val
    end
    |> case do
      nil ->
        stable_pleroma? = Pleroma.Application.stable?()

        current_stable_out =
          if stable_pleroma? do
            "stable"
          else
            "develop"
          end

        get_option(
          options,
          :ref,
          "You are currently running #{current_stable_out} version of Pleroma backend. What version of \"#{
            frontend
          }\" frontend you want to install? (\"stable\", \"develop\" or specific ref)",
          current_stable_out
        )

      config_value ->
        current_ref =
          case config_value do
            %{"ref" => ref} -> ref
            ref -> ref
          end

        get_option(
          options,
          :ref,
          "You are currently running \"#{current_ref}\" version of \"#{frontend}\" frontend. What version do you want to install? (\"stable\", \"develop\" or specific ref)",
          current_ref
        )
    end
  end

  defp get_bundle_meta("develop", gitlab_base_url, project) do
    url = "#{gitlab_api_url(gitlab_base_url, project)}/repository/branches"

    %{status: 200, body: json} = Tesla.get!(http_client(), url)

    %{"name" => name, "commit" => %{"short_id" => last_commit_ref}} =
      Enum.find(json, & &1["default"])

    %{
      "name" => name,
      "url" => build_url(gitlab_base_url, project, last_commit_ref)
    }
  end

  defp get_bundle_meta("stable", gitlab_base_url, project) do
    url = "#{gitlab_api_url(gitlab_base_url, project)}/releases"
    %{status: 200, body: json} = Tesla.get!(http_client(), url)

    [%{"commit" => %{"short_id" => commit_id}, "name" => name} | _] =
      Enum.sort(json, fn r1, r2 ->
        {:ok, date1, _offset} = DateTime.from_iso8601(r1["created_at"])
        {:ok, date2, _offset} = DateTime.from_iso8601(r2["created_at"])
        DateTime.compare(date1, date2) != :lt
      end)

    %{
      "name" => name,
      "url" => build_url(gitlab_base_url, project, commit_id)
    }
  end

  defp get_bundle_meta(ref, gitlab_base_url, project) do
    %{
      "name" => ref,
      "url" => build_url(gitlab_base_url, project, ref)
    }
  end

  defp install_bundle(bundle_url, dir) do
    http_client = http_client()

    with {:ok, %{status: 200, body: zip_body}} <- Tesla.get(http_client, bundle_url),
         {:ok, unzipped} <- :zip.unzip(zip_body, [:memory]) do
      File.rm_rf!(dir)

      Enum.each(unzipped, fn {path, data} ->
        path =
          path
          |> to_string()
          |> String.replace(~r/^dist\//, "")

        file_path = Path.join(dir, path)

        file_path
        |> Path.dirname()
        |> File.mkdir_p!()

        File.write!(file_path, data)
      end)
    else
      {:ok, %{status: 404}} ->
        {:error, "Bundle not found"}

      error ->
        {:error, error}
    end
  end

  defp gitlab_api_url(gitlab_base_url, project),
    do: "https://#{gitlab_base_url}/api/v4/projects/#{URI.encode_www_form(project)}"

  defp build_url(gitlab_base_url, project, ref),
    do: "https://#{gitlab_base_url}/#{project}/-/jobs/artifacts/#{ref}/download?job=build"

  defp http_client do
    middleware = [
      Tesla.Middleware.FollowRedirects,
      Tesla.Middleware.JSON
    ]

    Tesla.client(middleware)
  end
end
