# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FrontendController do
  use Pleroma.Web, :controller
  import Pleroma.Frontend, only: [get_primary_fe_opts: 0]

  def action(conn, _opts) do
    # `conn.private[:frontend]` can be unset if the function is called outside
    # of the standard controller pipeline
    fe_config = conn.private[:frontend] || get_primary_fe_opts()

    # can only be true for :primary frontend
    static_enabled? = Map.get(fe_config, :static, false)

    action_name = action_name(conn)

    {controller, action} =
      cond do
        static_enabled? and
            function_exported?(Pleroma.Web.Frontend.StaticController, action_name, 2) ->
          {Pleroma.Web.Frontend.StaticController, action_name}

        function_exported?(fe_config[:controller], action_name, 2) ->
          {fe_config[:controller], action_name}

        true ->
          {fe_config[:controller], :fallback}
      end

    conn
    # in case we are serving internal call
    |> put_private(:frontend, fe_config)
    |> put_view(Phoenix.Controller.__view__(controller))
    |> controller.call(controller.init(action))
  end

  @doc """
  Returns path to index.html file for the frontend from the given config.
  If config is not provided, config for the `:primary` frontend is fetched and used.
  If index.html file is not found for the requested frontend, the function fallback
  to looking the file at instance static directory and then, in case of failure,
  in priv/static directory.
  Path returned in case of success is guaranteed to be existing file.
  """
  @spec index_file_path(Map.t()) :: {:ok, String.t()} | {:error, String.t()}
  def index_file_path(fe_config \\ nil) do
    filename = "index.html"
    instance_base_path = Pleroma.Config.get([:instance, :static_dir], "instance/static/")

    %{"name" => name, "ref" => ref} =
      with nil <- fe_config do
        Pleroma.Frontend.get_primary_fe_opts()[:config]
      end

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
        {:error, "index.html file was not found"}
    end
  end
end
