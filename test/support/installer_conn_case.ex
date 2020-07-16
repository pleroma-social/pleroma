# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.InstallerWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Pleroma.Tests.Helpers

      import Plug.Conn
      import Phoenix.ConnTest

      alias Pleroma.InstallerWeb.Router.Helpers, as: Routes

      @endpoint Pleroma.InstallerWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Pleroma.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Pleroma.Repo, {:shared, self()})
    end

    %{conn: Phoenix.ConnTest.build_conn()}
  end
end
