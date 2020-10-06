# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.MediaController do
  use Pleroma.Web, :controller

  alias Pleroma.Object
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.Plugs.OAuthScopesPlug

  action_fallback(Pleroma.Web.MastodonAPI.FallbackController)
  plug(Majic.Plug, [pool: Pleroma.MajicPool] when action in [:create, :create2])
  plug(Pleroma.Web.ApiSpec.CastAndValidate)
  plug(:put_view, Pleroma.Web.MastodonAPI.StatusView)

  plug(OAuthScopesPlug, %{scopes: ["read:media"]} when action == :show)
  plug(OAuthScopesPlug, %{scopes: ["write:media"]} when action != :show)

  defdelegate open_api_operation(action), to: Pleroma.Web.ApiSpec.MediaOperation

  @doc "POST /api/v1/media"
  def create(%{assigns: %{user: user}, body_params: %{file: file} = data} = conn, _) do
    with {:ok, object} <-
           ActivityPub.upload(
             file,
             actor: User.ap_id(user),
             description: Map.get(data, :description),
             filename: Map.get(data, :filename)
           ) do
      attachment_data = Map.put(object.data, "id", object.id)

      render(conn, "attachment.json", %{attachment: attachment_data})
    end
  end

  def create(_conn, _data), do: {:error, :bad_request}

  @doc "POST /api/v2/media"
  def create2(%{assigns: %{user: user}, body_params: %{file: file} = data} = conn, _) do
    with {:ok, object} <-
           ActivityPub.upload(
             file,
             actor: User.ap_id(user),
             description: Map.get(data, :description),
             filename: Map.get(data, :filename)
           ) do
      attachment_data = Map.put(object.data, "id", object.id)

      conn
      |> put_status(202)
      |> render("attachment.json", %{attachment: attachment_data})
    end
  end

  def create2(_conn, _data), do: {:error, :bad_request}

  @doc "PUT /api/v1/media/:id"
  def update(
        %{assigns: %{user: user}, body_params: body_params} = conn,
        %{id: id}
      ) do
    with %Object{} = object <- Object.get_by_id(id),
         :ok <- Object.authorize_access(object, user),
         params <- prepare_update_params(body_params),
         :ok <- validate_filename(params["filename"], hd(object.data["url"])),
         {:ok, %Object{data: data}} <- Object.update_data(object, params) do
      attachment_data = Map.put(data, "id", object.id)

      render(conn, "attachment.json", %{attachment: attachment_data})
    end
  end

  @doc "GET /api/v1/media/:id"
  def show(%{assigns: %{user: user}} = conn, %{id: id}) do
    with %Object{data: data, id: object_id} = object <- Object.get_by_id(id),
         :ok <- Object.authorize_access(object, user) do
      attachment_data = Map.put(data, "id", object_id)

      render(conn, "attachment.json", %{attachment: attachment_data})
    end
  end

  def show(_conn, _data), do: {:error, :bad_request}

  defp prepare_update_params(body_params) do
    body_params
    |> Map.take([:description, :filename])
    |> Enum.into(%{}, fn
      {:description, description} ->
        {"name", description}

      {:filename, filename} ->
        {"filename", filename}
    end)
  end

  defp validate_filename(nil, _), do: :ok

  defp validate_filename(filename, %{"href" => href}) do
    if Path.extname(filename) == Path.extname(href) do
      :ok
    else
      {:error, :invalid_filename_extension}
    end
  end
end
