# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Frontend do
  @type primary_fe_opts :: %{config: Map.t(), controller: Module.t(), static: boolean()}

  @spec get_primary_fe_opts() :: primary_fe_opts()
  def get_primary_fe_opts,
    do: [:frontends] |> Pleroma.Config.get(%{}) |> Enum.into(%{}) |> get_primary_fe_opts()

  @spec get_primary_fe_opts(Map.t()) :: primary_fe_opts()
  def get_primary_fe_opts(%{primary: %{"name" => "none"}} = fe_config) do
    %{
      config: %{},
      controller: Pleroma.Web.Frontend.HeadlessController,
      static: fe_config[:static] || false
    }
  end

  def get_primary_fe_opts(fe_config) do
    %{
      config: fe_config[:primary],
      controller:
        Module.concat([
          Pleroma.Web.Frontend,
          String.capitalize(fe_config[:primary]["name"]) <> "Controller"
        ]),
      static: fe_config[:static] || false
    }
  end

  @doc """
  Returns path to the requested file for the frontend from the given config.
  If config is not provided, config for the `:primary` frontend is fetched and used.
  If the requested file is not found for the frontend, the function fallback
  to looking the file at instance static directory and then, in case of failure,
  in priv/static directory.
  Path returned in case of success is guaranteed to be of existing file.
  """
  @spec fe_file_path(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def fe_file_path(filename, config \\ nil) do
    %{"name" => name, "ref" => ref} =
      with nil <- config do
        get_primary_fe_opts()[:config]
      end

    instance_base_path = Pleroma.Config.get([:instance, :static_dir], "instance/static/")

    frontend_path = Path.join([instance_base_path, "frontends", name, ref, filename])
    instance_path = Path.join([instance_base_path, filename])
    priv_path = Application.app_dir(:pleroma, ["priv", "static", filename])

    cond do
      File.exists?(instance_path) ->
        {:ok, instance_path}

      File.exists?(frontend_path) ->
        {:ok, frontend_path}

      File.exists?(priv_path) ->
        {:ok, priv_path}

      true ->
        {:error,
         "File #{filename} was not found in #{inspect([instance_path, frontend_path, priv_path])}"}
    end
  end
end
