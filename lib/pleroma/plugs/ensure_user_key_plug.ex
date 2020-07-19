# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Plugs.EnsureUserKeyPlug do
  alias Pleroma.User
  import Plug.Conn

  def init(opts) do
    opts
  end

  def call(%{assigns: %{user: _}} = conn, _), do: conn

  def call(conn, _) do
    with user_id <- get_session(conn, :user_id),
         true <- is_binary(user_id),
         %User{} = user <- User.get_by_id(user_id) do
      assign(conn, :user, user)
    else
      _ -> assign(conn, :user, nil)
    end
  end
end
