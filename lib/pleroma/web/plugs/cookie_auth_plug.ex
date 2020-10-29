# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.CookieAuthPlug do
  alias Pleroma.User
  import Plug.Conn

  def init(opts) do
    opts
  end

  # If the user is already assigned (by a bearer token, probably), skip ahead.
  def call(%{assigns: %{user: %User{}}} = conn, _), do: conn

  # Authenticate with a session cookie, if available.
  # For staticly-rendered pages (like the OAuth form)
  # this is the only way it can authenticate.
  def call(conn, _) do
    with user_id when is_binary(user_id) <- get_session(conn, :user_id),
         %User{} = user <- User.get_by_id(user_id) do
      assign(conn, :user, user)
    else
      _ -> conn
    end
  end
end
