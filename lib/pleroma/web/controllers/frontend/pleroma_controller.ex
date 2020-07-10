# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Frontend.PleromaController do
  use Pleroma.Web, :controller
  use Pleroma.Web.Frontend.DefaultController

  alias Pleroma.User

  def index_with_meta_and_user(conn, %{"maybe_nickname_or_id" => maybe_nickname_or_id} = params) do
    case User.get_cached_by_nickname_or_id(maybe_nickname_or_id) do
      %User{} = user ->
        index_with_meta(conn, %{user: user})

      _ ->
        index(conn, params)
    end
  end

  defdelegate registration_page(conn, params), to: __MODULE__, as: :index_with_preload
end
