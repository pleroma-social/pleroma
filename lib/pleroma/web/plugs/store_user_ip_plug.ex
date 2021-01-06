# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.StoreUserIpPlug do
  @moduledoc """
  Stores the user's last known IP address in the database if enabled.
  User IP addresses are shown in AdminAPI.
  """

  alias Pleroma.Config
  alias Pleroma.User
  import Plug.Conn

  @behaviour Plug

  def init(_), do: nil

  # IP address hasn't changed, so skip
  def call(
        %{remote_ip: ip, assigns: %{remote_ip_found: true, user: %User{last_known_ip: ip}}} =
          conn,
        _
      ),
      do: conn

  # Store user IP if enabled
  def call(%{remote_ip: ip, assigns: %{remote_ip_found: true, user: %User{} = user}} = conn, _) do
    with true <- Config.get([__MODULE__, :enabled]),
         {:ok, %User{} = user} <- User.update_last_known_ip(user, ip) do
      assign(conn, :user, user)
    else
      _ -> conn
    end
  end

  # Fail silently
  def call(conn, _), do: conn
end
