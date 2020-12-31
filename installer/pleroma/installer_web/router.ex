# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.InstallerWeb.Router do
  use Pleroma.InstallerWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", Pleroma.InstallerWeb do
    pipe_through(:browser)

    get("/", SetupController, :index)

    post("/credentials", SetupController, :save_credentials)

    get("/check_database_and_write_config", SetupController, :check_database_and_write_config)

    get("/migrations", SetupController, :migrations)
    get("/run_migrations", SetupController, :run_migrations)

    get("/config", SetupController, :config)
    post("/config", SetupController, :save_config)
  end
end
