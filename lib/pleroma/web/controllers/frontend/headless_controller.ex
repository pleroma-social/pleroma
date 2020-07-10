# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Frontend.HeadlessController do
  use Pleroma.Web, :controller

  def index_with_preload(conn, _params) do
    conn
    |> put_status(404)
    |> text("")
  end
end
