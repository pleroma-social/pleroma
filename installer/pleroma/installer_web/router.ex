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

    get("/config", SetupController, :config)
    post("/config", SetupController, :save_config)

    get("/credentials_setup", SetupController, :credentials_setup)
    post("/create_psql_file", SetupController, :create_psql_file)
    get("/save_generated_credentials", SetupController, :save_generated_credentials)

    get("/credentials", SetupController, :credentials)
    post("/credentials", SetupController, :save_credentials)
  end
end
