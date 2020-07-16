# # Pleroma: A lightweight social networking server
# # Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# # SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Config.EnvironmentTest do
  use Pleroma.DataCase

  import Pleroma.Factory

  alias Pleroma.Config.Environment

  setup do: clear_config(:configurable_from_database, true)

  test "transfer config values from db to env" do
    refute Application.get_env(:pleroma, :test_key)
    refute Application.get_env(:idna, :test_key)
    refute Application.get_env(:quack, :test_key)
    refute Application.get_env(:postgrex, :test_key)
    initial = Application.get_env(:logger, :level)

    insert(:config, key: :test_key, value: [live: 2, com: 3])
    insert(:config, group: :idna, key: :test_key, value: [live: 15, com: 35])
    insert(:config, group: :quack, key: :test_key, value: [:test_value1, :test_value2])
    insert(:config, group: :postgrex, key: :test_key, value: :value)
    insert(:config, group: :logger, key: :level, value: :debug)

    Environment.load_and_update()

    assert Application.get_env(:pleroma, :test_key) == [live: 2, com: 3]
    assert Application.get_env(:idna, :test_key) == [live: 15, com: 35]
    assert Application.get_env(:quack, :test_key) == [:test_value1, :test_value2]
    assert Application.get_env(:logger, :level) == :debug
    assert Application.get_env(:postgrex, :test_key) == :value

    on_exit(fn ->
      Application.delete_env(:pleroma, :test_key)
      Application.delete_env(:idna, :test_key)
      Application.delete_env(:quack, :test_key)
      Application.delete_env(:postgrex, :test_key)
      Application.put_env(:logger, :level, initial)
    end)
  end

  test "transfer config values for 1 group and some keys" do
    level = Application.get_env(:quack, :level)
    meta = Application.get_env(:quack, :meta)

    insert(:config, group: :quack, key: :level, value: :info)
    insert(:config, group: :quack, key: :meta, value: [:none])

    Environment.load_and_update()

    assert Application.get_env(:quack, :level) == :info
    assert Application.get_env(:quack, :meta) == [:none]
    default = Pleroma.Config.Holder.default_config(:quack, :webhook_url)
    assert Application.get_env(:quack, :webhook_url) == default

    on_exit(fn ->
      Application.put_env(:quack, :level, level)
      Application.put_env(:quack, :meta, meta)
    end)
  end

  test "transfer config values with full subkey update" do
    clear_config(:emoji)
    clear_config(:assets)

    insert(:config, key: :emoji, value: [groups: [a: 1, b: 2]])
    insert(:config, key: :assets, value: [mascots: [a: 1, b: 2]])

    Environment.load_and_update()

    emoji_env = Application.get_env(:pleroma, :emoji)
    assert emoji_env[:groups] == [a: 1, b: 2]
    assets_env = Application.get_env(:pleroma, :assets)
    assert assets_env[:mascots] == [a: 1, b: 2]
  end
end
