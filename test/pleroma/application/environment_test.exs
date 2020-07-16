# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.EnvironmentTest do
  use Pleroma.DataCase

  import Pleroma.Factory

  alias Pleroma.Application.Environment

  setup do: clear_config(:configurable_from_database, true)

  describe "load_from_db_and_update/0" do
    test "transfer config values from db to env" do
      refute Application.get_env(:pleroma, :test_key)
      refute Application.get_env(:idna, :test_key)
      refute Application.get_env(:quack, :test_key)
      refute Application.get_env(:postgrex, :test_key)
      initial = Application.get_env(:logger, :level)

      insert(:config, key: :test_key, value: [live: 2, com: 3])
      insert(:config, group: :idna, key: :test_key, value: [live: 15, com: 35])

      insert(:config,
        group: :quack,
        key: nil,
        value: [test_key: [key1: :test_value1, key2: :test_value2]]
      )

      insert(:config, group: :logger, key: nil, value: [level: :debug])

      Environment.load_from_db_and_update()

      assert Application.get_env(:pleroma, :test_key) == [live: 2, com: 3]
      assert Application.get_env(:idna, :test_key) == [live: 15, com: 35]
      assert Application.get_env(:quack, :test_key) == [key1: :test_value1, key2: :test_value2]
      assert Application.get_env(:logger, :level) == :debug

      on_exit(fn ->
        Application.delete_env(:pleroma, :test_key)
        Application.delete_env(:idna, :test_key)
        Application.delete_env(:quack, :test_key)
        Application.delete_env(:postgrex, :test_key)
        Application.put_env(:logger, :level, initial)
      end)
    end

    test "transfer config values for 1 group and some keys" do
      quack_env = Application.get_all_env(:quack)

      insert(:config, group: :quack, key: nil, value: [level: :info, meta: [:none]])

      Environment.load_from_db_and_update()

      assert Application.get_env(:quack, :level) == :info
      assert Application.get_env(:quack, :meta) == [:none]
      default = Pleroma.Config.Holder.default_config(:quack, :webhook_url)
      assert Application.get_env(:quack, :webhook_url) == default

      on_exit(fn ->
        Application.put_all_env(quack: quack_env)
      end)
    end

    test "transfer config values with full subkey update" do
      clear_config(:emoji)
      clear_config(:assets)

      insert(:config, key: :emoji, value: [groups: [a: 1, b: 2]])
      insert(:config, key: :assets, value: [mascots: [a: 1, b: 2]])

      Environment.load_from_db_and_update()

      emoji_env = Application.get_env(:pleroma, :emoji)
      assert emoji_env[:groups] == [a: 1, b: 2]
      assets_env = Application.get_env(:pleroma, :assets)
      assert assets_env[:mascots] == [a: 1, b: 2]
    end
  end

  test "update/1 loads file content into env" do
    clear_config(:first_setting)
    clear_config(:second_setting)
    clear_config(Pleroma.Repo)
    clear_config(Pleroma.Web.Endpoint)
    clear_config(Pleroma.InstallerWeb.Endpoint)
    clear_config(:env)
    clear_config(:database)
    clear_config(:configurable_from_database)
    clear_config(:ecto_repos)

    quack_level = Application.get_env(:quack, :level)
    postgrex_json_lib = Application.get_env(:postrgex, :json_library)

    assert Pleroma.Config.get(:configurable_from_database) == true

    refute Pleroma.Config.get([Pleroma.Web.Endpoint, :key])
    refute Pleroma.Config.get([Pleroma.InstallerWeb.Endpoint, :key])
    refute Application.get_env(:http_signatures, :key)
    refute Application.get_env(:web_push_encryption, :key)
    refute Application.get_env(:floki, :key)

    assert Environment.update("test/fixtures/config/temp.secret.exs") == :ok

    assert Pleroma.Config.get(:first_setting) == [key: "value", key2: [Pleroma.Repo]]
    assert Pleroma.Config.get(:second_setting) == [key: "value2", key2: ["Activity"]]
    assert Pleroma.Config.get([Pleroma.Web.Endpoint, :key]) == :val
    assert Pleroma.Config.get([Pleroma.InstallerWeb.Endpoint, :key]) == :val
    assert Pleroma.Config.get([:database, :rum_enabled])
    assert Application.get_env(:postgrex, :json_library) == Poison
    assert Application.get_env(:http_signatures, :key) == :val
    assert Application.get_env(:web_push_encryption, :key) == :val
    assert Application.get_env(:floki, :key) == :val

    refute Pleroma.Config.get(:configurable_from_database)

    on_exit(fn ->
      Application.put_env(:quack, :level, quack_level)
      Application.put_env(:postgrex, :json_library, postgrex_json_lib)

      Pleroma.Config.delete([Pleroma.Web.Endpoint, :key])
      Pleroma.Config.delete([Pleroma.InstallerWeb.Endpoint, :key])

      Application.delete_env(:http_signatures, :key)
      Application.delete_env(:web_push_encryption, :key)
      Application.delete_env(:floki, :key)
    end)
  end

  describe "update/2 :ex_syslogger" do
    setup do
      initial = Application.get_env(:logger, :ex_syslogger)

      config =
        insert(:config,
          group: :logger,
          key: nil,
          value: [
            ex_syslogger: [
              level: :warn,
              ident: "pleroma",
              format: "$metadata[$level] $message",
              metadata: [:request_id, :key]
            ]
          ]
        )

      on_exit(fn -> Application.put_env(:logger, :ex_syslogger, initial) end)
      [config: config, initial: initial]
    end

    test "changing", %{config: config} do
      assert Environment.update([config]) == :ok

      env = Application.get_env(:logger, :ex_syslogger)
      assert env[:level] == :warn
      assert env[:metadata] == [:request_id, :key]
    end

    test "deletion", %{config: config, initial: initial} do
      assert Environment.update([config]) == :ok

      {:ok, config} = Pleroma.ConfigDB.delete(config)
      assert Environment.update([config]) == :ok

      env = Application.get_env(:logger, :ex_syslogger)

      assert env == initial
    end
  end

  describe "update/2 :console" do
    setup do
      initial = Application.get_env(:logger, :console)

      config =
        insert(:config,
          group: :logger,
          key: nil,
          value: [
            console: [
              level: :info,
              format: "$time $metadata[$level]",
              metadata: [:request_id, :key]
            ]
          ]
        )

      on_exit(fn -> Application.put_env(:logger, :console, initial) end)
      [config: config, initial: initial]
    end

    test "change", %{config: config} do
      assert Environment.update([config]) == :ok
      env = Application.get_env(:logger, :console)
      assert env[:level] == :info
      assert env[:format] == "$time $metadata[$level]"
      assert env[:metadata] == [:request_id, :key]
    end

    test "deletion", %{config: config, initial: initial} do
      assert Environment.update([config]) == :ok
      {:ok, config} = Pleroma.ConfigDB.delete(config)
      assert Environment.update([config]) == :ok

      env = Application.get_env(:logger, :console)
      assert env == initial
    end
  end

  describe "update/2 :backends" do
    setup do
      initial = Application.get_all_env(:logger)

      config =
        insert(:config, group: :logger, key: nil, value: [backends: [:console, :ex_syslogger]])

      on_exit(fn -> Application.put_all_env(logger: initial) end)

      [config: config, initial: initial]
    end

    test "change", %{config: config} do
      assert Environment.update([config]) == :ok
      env = Application.get_all_env(:logger)
      assert env[:backends] == [:console, :ex_syslogger]
    end

    test "deletion", %{config: config, initial: initial} do
      assert Environment.update([config]) == :ok
      {:ok, config} = Pleroma.ConfigDB.delete(config)
      assert Environment.update([config])

      env = Application.get_all_env(:logger)
      assert env == initial
    end
  end

  describe "update/2 logger settings" do
    setup do
      initial = Application.get_all_env(:logger)

      config =
        insert(:config,
          group: :logger,
          key: nil,
          value: [
            console: [
              level: :info,
              format: "$time $metadata[$level]",
              metadata: [:request_id, :key]
            ],
            ex_syslogger: [
              level: :warn,
              ident: "pleroma",
              format: "$metadata[$level] $message",
              metadata: [:request_id, :key]
            ],
            backends: [:console, :ex_syslogger]
          ]
        )

      on_exit(fn -> Application.put_all_env(logger: initial) end)
      [config: config]
    end

    test "change", %{config: config} do
      assert Environment.update([config]) == :ok

      env =
        :logger
        |> Application.get_all_env()
        |> Keyword.take([:backends, :console, :ex_syslogger])

      assert env[:console] == config.value[:console]
      assert env[:ex_syslogger] == config.value[:ex_syslogger]
      assert env[:backends] == config.value[:backends]
    end
  end

  test "update/2 for change without key :cors_plug" do
    config =
      insert(:config,
        group: :cors_plug,
        key: nil,
        value: [max_age: 300, methods: ["GET"]]
      )

    assert Environment.update([config]) == :ok

    env = Application.get_all_env(:cors_plug)

    assert env[:max_age] == 300
    assert env[:methods] == ["GET"]
  end
end
