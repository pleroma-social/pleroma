# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.InstallerWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :pleroma

  @session_options [
    store: :cookie,
    key: "_pleroma_installer_key",
    signing_salt: "4aGH1qnr"
  ]

  plug(Plug.Static,
    at: "/",
    from: {:pleroma, "priv/static/installer"},
    gzip: false,
    only: ~w(css fonts images js favicon.ico robots.txt)
  )

  if code_reloading? do
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.Parsers,
    parsers: [:urlencoded],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Session, @session_options)
  plug(Pleroma.InstallerWeb.Router)
end
