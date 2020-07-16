# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Config.LoaderTest do
  use ExUnit.Case, async: true

  alias Pleroma.Config.Loader

  test "read/1" do
    config = Loader.read!("test/fixtures/config/temp.secret.exs")
    assert config[:pleroma][:first_setting][:key] == "value"
    assert config[:pleroma][:first_setting][:key2] == [Pleroma.Repo]
    assert config[:quack][:level] == :info
  end

  test "filter/1" do
    config = Loader.read!("test/fixtures/config/temp.secret.exs")

    filtered_config = Loader.filter(config)

    refute filtered_config[:postgrex]
    refute filtered_config[:tesla]
    refute filtered_config[:phoenix]
    refute filtered_config[:tz_data]
    refute filtered_config[:http_signatures]
    refute filtered_config[:web_push_encryption]
    refute filtered_config[:floki]

    refute filtered_config[:pleroma][Pleroma.Repo]
    refute filtered_config[:pleroma][Pleroma.Web.Endpoint]
    refute filtered_config[:pleroma][Pleroma.InstallerWeb.Endpoint]
    refute filtered_config[:pleroma][:env]
    refute filtered_config[:pleroma][:configurable_from_database]
    refute filtered_config[:pleroma][:database]
    refute filtered_config[:pleroma][:ecto_repos]
    refute filtered_config[:pleroma][Pleroma.Gun]
    refute filtered_config[:pleroma][Pleroma.ReverseProxy.Client]

    assert config[:pleroma][:first_setting][:key] == "value"
    assert config[:pleroma][:first_setting][:key2] == [Pleroma.Repo]
    assert config[:quack][:level] == :info
    assert config[:pleroma][:second_setting][:key] == "value2"
    assert config[:pleroma][:second_setting][:key2] == ["Activity"]
  end
end
