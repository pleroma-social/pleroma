# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

use Mix.Config

config :pleroma, :first_setting, key: "value", key2: [Pleroma.Repo]

config :pleroma, :second_setting, key: "value2", key2: ["Activity"]

config :quack, level: :info

config :pleroma, Pleroma.Repo, pool: Ecto.Adapters.SQL.Sandbox

config :pleroma, Pleroma.Web.Endpoint, key: :val

config :pleroma, Pleroma.InstallerWeb.Endpoint, key: :val

config :pleroma, env: :test

config :pleroma, :database, rum_enabled: true

config :pleroma, configurable_from_database: false

config :pleroma, ecto_repos: [Pleroma.Repo]

config :pleroma, Pleroma.Gun, Pleroma.GunMock

config :pleroma, Pleroma.ReverseProxy.Client, Pleroma.ReverseProxy.Client

config :postgrex, :json_library, Poison

config :tesla, adapter: Tesla.Mock

config :tzdata, http_client: Pleroma.HTTP

config :http_signatures, key: :val

config :web_push_encryption, key: :val

config :floki, key: :val
