# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Config.Loader do
  @reject_groups [
    :postgrex,
    :tesla,
    :phoenix,
    :tzdata,
    :http_signatures,
    :web_push_encryption,
    :floki,
    :pbkdf2_elixir
  ]

  @reject_keys [
    Pleroma.Repo,
    Pleroma.Web.Endpoint,
    Pleroma.InstallerWeb.Endpoint,
    :env,
    :configurable_from_database,
    :database,
    :ecto_repos,
    Pleroma.Gun,
    Pleroma.ReverseProxy.Client,
    Pleroma.Web.Auth.Authenticator
  ]

  if Code.ensure_loaded?(Config.Reader) do
    @reader Config.Reader
    @config_header "import Config\r\n\r\n"
  else
    # support for Elixir less than 1.9
    @reader Mix.Config
    @config_header "use Mix.Config\r\n\r\n"
  end

  @spec read!(Path.t()) :: keyword()
  def read!(path), do: @reader.read!(path)

  @spec merge(keyword(), keyword()) :: keyword()
  def merge(c1, c2), do: @reader.merge(c1, c2)

  @spec config_header() :: String.t()
  def config_header, do: @config_header

  @spec default_config() :: keyword()
  def default_config do
    config =
      "config/config.exs"
      |> read!()
      |> filter()

    logger_config =
      :logger
      |> Application.get_all_env()
      |> Enum.filter(fn {key, _} -> key in [:backends, :console, :ex_syslogger] end)

    merge(config, logger: logger_config)
  end

  @spec filter(keyword()) :: keyword()
  def filter(configs) do
    Enum.reduce(configs, [], fn
      {group, _settings}, group_acc when group in @reject_groups ->
        group_acc

      {group, settings}, group_acc ->
        Enum.reduce(settings, group_acc, fn
          {key, _value}, acc when key in @reject_keys -> acc
          setting, acc -> Keyword.update(acc, group, [setting], &Keyword.merge(&1, [setting]))
        end)
    end)
  end
end
