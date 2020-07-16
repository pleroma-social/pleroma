# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.InstallerWeb do
  def controller do
    quote do
      use Phoenix.Controller, namespace: Pleroma.InstallerWeb

      import Plug.Conn
      alias Pleroma.InstallerWeb.Router.Helpers, as: Routes
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "installer/pleroma/installer_web/templates",
        namespace: Pleroma.InstallerWeb

      import Phoenix.Controller,
        only: [get_flash: 1, get_flash: 2, view_module: 1, view_template: 1]

      use Phoenix.HTML

      import Pleroma.InstallerWeb.ErrorHelpers
      import Pleroma.Web.Gettext

      alias Pleroma.InstallerWeb.Router.Helpers, as: Routes
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
