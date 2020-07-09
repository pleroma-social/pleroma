# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Frontend.PleromaController do
  use Pleroma.Web, :controller
  use Pleroma.Web.Frontend.DefaultController

  require Logger

  alias Pleroma.User
  alias Pleroma.Web.Metadata
  alias Pleroma.Web.Preload

  def index_with_meta(conn, %{"maybe_nickname_or_id" => maybe_nickname_or_id} = params) do
    case User.get_cached_by_nickname_or_id(maybe_nickname_or_id) do
      %User{} = user ->
        index_with_meta(conn, %{user: user})

      _ ->
        index(conn, params)
    end
  end

  # not intended to be matched from router, but can be called from the app internally
  def index_with_meta(conn, params) do
    {:ok, path} = index_file_path()
    {:ok, index_content} = File.read(path)

    tags =
      try do
        Metadata.build_tags(params)
      rescue
        e ->
          Logger.error(
            "Metadata rendering for #{conn.request_path} failed.\n" <>
              Exception.format(:error, e, __STACKTRACE__)
          )

          ""
      end

    preloads = preload_data(conn, params)

    response = String.replace(index_content, "<!--server-generated-meta-->", tags <> preloads)

    html(conn, response)
  end

  def index_with_preload(conn, params) do
    {:ok, path} = index_file_path()
    {:ok, index_content} = File.read(path)
    preloads = preload_data(conn, params)

    response = String.replace(index_content, "<!--server-generated-meta-->", preloads)

    html(conn, response)
  end

  defdelegate registration_page(conn, params), to: __MODULE__, as: :index

  defp preload_data(conn, params) do
    try do
      Preload.build_tags(conn, params)
    rescue
      e ->
        Logger.error(
          "Preloading for #{conn.request_path} failed.\n" <>
            Exception.format(:error, e, __STACKTRACE__)
        )

        ""
    end
  end
end
