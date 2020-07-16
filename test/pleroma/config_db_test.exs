# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.ConfigDBTest do
  use Pleroma.DataCase, async: true
  import Pleroma.Factory
  alias Pleroma.ConfigDB

  test "get_by_params/1" do
    config = insert(:config)
    insert(:config)

    assert config == ConfigDB.get_by_params(%{group: config.group, key: config.key})
  end

  test "all_as_keyword/0" do
    saved = insert(:config)
    insert(:config, group: ":quack", key: ":level", value: :info)
    insert(:config, group: ":quack", key: ":meta", value: [:none])

    insert(:config,
      group: ":quack",
      key: ":webhook_url",
      value: "https://hooks.slack.com/services/KEY/some_val"
    )

    config = ConfigDB.all_as_keyword()

    assert config[:pleroma] == [
             {saved.key, saved.value}
           ]

    assert config[:quack][:level] == :info
    assert config[:quack][:meta] == [:none]
    assert config[:quack][:webhook_url] == "https://hooks.slack.com/services/KEY/some_val"
  end

  describe "update_or_create/1" do
    test "common" do
      config1 = insert(:config, value: [])
      key2 = :another_key

      params = [
        %{group: :pleroma, key: config1.key, value: [a: 1, b: 2, c: "new_value"]},
        %{group: :pleroma, key: key2, value: [new_val: "another_value"]}
      ]

      assert Repo.all(ConfigDB) |> length() == 1

      Enum.each(params, &ConfigDB.update_or_create(&1))

      assert Repo.all(ConfigDB) |> length() == 2

      config1 = ConfigDB.get_by_params(%{group: config1.group, key: config1.key})
      config2 = ConfigDB.get_by_params(%{group: :pleroma, key: key2})

      assert config1.value == [a: 1, b: 2, c: "new_value"]
      assert config2.value == [new_val: "another_value"]
    end

    test "partial update" do
      config = insert(:config, value: [key1: "val1", key2: :val2])

      {:ok, config} =
        ConfigDB.update_or_create(%{
          group: config.group,
          key: config.key,
          value: [key1: :val1, key3: :val3]
        })

      updated = ConfigDB.get_by_params(%{group: config.group, key: config.key})

      assert config.value == updated.value
      assert updated.value[:key1] == :val1
      assert updated.value[:key2] == :val2
      assert updated.value[:key3] == :val3
    end

    test "deep merge" do
      config = insert(:config, value: [key1: "val1", key2: [k1: :v1, k2: "v2"]])

      {:ok, config} =
        ConfigDB.update_or_create(%{
          group: config.group,
          key: config.key,
          value: [key1: :val1, key2: [k2: :v2, k3: :v3], key3: :val3]
        })

      updated = ConfigDB.get_by_params(%{group: config.group, key: config.key})

      assert config.value == updated.value
      assert updated.value[:key1] == :val1
      assert updated.value[:key2] == [k1: :v1, k2: :v2, k3: :v3]
      assert updated.value[:key3] == :val3
    end

    test "only full update for groups without keys" do
      config = insert(:config, group: :cors_plug, key: nil, value: [max_age: 18])

      {:ok, _config} =
        ConfigDB.update_or_create(%{
          group: config.group,
          key: nil,
          value: [max_age: 25, credentials: true]
        })

      updated = ConfigDB.get_by_params(%{group: config.group, key: config.key})
      assert updated.value == [max_age: 25, credentials: true]
    end

    test "only full update for some subkeys" do
      config1 =
        insert(:config,
          key: ":emoji",
          value: [groups: [a: 1, b: 2], key: [a: 1]]
        )

      config2 =
        insert(:config,
          key: ":assets",
          value: [mascots: [a: 1, b: 2], key: [a: 1]]
        )

      {:ok, _config} =
        ConfigDB.update_or_create(%{
          group: config1.group,
          key: config1.key,
          value: [groups: [c: 3, d: 4], key: [b: 2]]
        })

      {:ok, _config} =
        ConfigDB.update_or_create(%{
          group: config2.group,
          key: config2.key,
          value: [mascots: [c: 3, d: 4], key: [b: 2]]
        })

      updated1 = ConfigDB.get_by_params(%{group: config1.group, key: config1.key})
      updated2 = ConfigDB.get_by_params(%{group: config2.group, key: config2.key})

      assert updated1.value == [groups: [c: 3, d: 4], key: [a: 1, b: 2]]
      assert updated2.value == [mascots: [c: 3, d: 4], key: [a: 1, b: 2]]
    end
  end

  describe "delete_or_update/1" do
    test "error on deleting non existing setting" do
      assert {:ok, nil} == ConfigDB.delete_or_update(%{group: :pleroma, key: :key})
    end

    test "full delete" do
      config = insert(:config)
      {:ok, deleted} = ConfigDB.delete_or_update(%{group: config.group, key: config.key})
      assert Ecto.get_meta(deleted, :state) == :deleted
      refute ConfigDB.get_by_params(%{group: config.group, key: config.key})
    end

    test "partial subkeys delete" do
      config = insert(:config, value: [groups: [a: 1, b: 2], key: [a: 1]])

      {:ok, deleted} =
        ConfigDB.delete_or_update(%{group: config.group, key: config.key, subkeys: [:groups]})

      assert Ecto.get_meta(deleted, :state) == :loaded

      assert deleted.value == [key: [a: 1]]

      updated = ConfigDB.get_by_params(%{group: config.group, key: config.key})

      assert updated.value == deleted.value
    end

    test "full delete if remaining value after subkeys deletion is empty list" do
      config = insert(:config, value: [groups: [a: 1, b: 2]])

      {:ok, deleted} =
        ConfigDB.delete_or_update(%{group: config.group, key: config.key, subkeys: [:groups]})

      assert Ecto.get_meta(deleted, :state) == :deleted

      refute ConfigDB.get_by_params(%{group: config.group, key: config.key})
    end

    test "delete struct" do
      config = insert(:config)
      {:ok, config} = ConfigDB.delete(config)
      assert Ecto.get_meta(config, :state) == :deleted
      assert Pleroma.Repo.aggregate(ConfigDB, :count) == 0
    end
  end

  test "all/0" do
    config = insert(:config)

    assert [^config] = ConfigDB.all()
  end

  describe "reduce_defaults_and_merge_with_changes/2" do
    test "common changes" do
      defaults = [
        pleroma: [
          key1: [k1: 1, k2: 1, k3: 1],
          key2: [k1: 2, k2: 2, k3: 2]
        ],
        logger: [k1: 3, k2: 3]
      ]

      config1 = insert(:config, key: :key1, value: [k1: 4, k2: 4])
      config2 = insert(:config, key: :key2, value: [k1: 5, k2: 5])

      {changes, [logger: [k1: 3, k2: 3]]} =
        ConfigDB.reduce_defaults_and_merge_with_changes([config1, config2], defaults)

      Enum.each(changes, fn
        %{key: :key1, value: value} ->
          assert value == [k3: 1, k1: 4, k2: 4]

        %{key: :key2, value: value} ->
          assert value == [k3: 2, k1: 5, k2: 5]
      end)
    end

    test "changes for group without key" do
      defaults = [
        cors_plug: [
          max_age: 86_400,
          methods: ["POST", "PUT", "DELETE", "GET", "PATCH", "OPTIONS"]
        ],
        pleroma: [key1: [k1: 1, k2: 1, k3: 1]]
      ]

      config = insert(:config, group: :cors_plug, key: nil, value: [max_age: 60_000])

      {[change], [pleroma: [key1: [k1: 1, k2: 1, k3: 1]]]} =
        ConfigDB.reduce_defaults_and_merge_with_changes([config], defaults)

      assert change.value == [
               methods: ["POST", "PUT", "DELETE", "GET", "PATCH", "OPTIONS"],
               max_age: 60_000
             ]
    end

    test "for logger backend setting and others" do
      defaults = [
        logger: [
          ex_syslogger: [k1: 1, k2: 1],
          console: [k1: 2, k2: 2],
          backends: [:ex_syslogger, :console],
          key: 1
        ],
        pleroma: [key1: 1, key2: 2]
      ]

      logger =
        insert(:config,
          group: :logger,
          key: nil,
          value: [ex_syslogger: [k1: 3, k2: 4], backends: [:console]]
        )

      {[change], [pleroma: [key1: 1, key2: 2]]} =
        ConfigDB.reduce_defaults_and_merge_with_changes([logger], defaults)

      assert change.value == [
               console: [k1: 2, k2: 2],
               key: 1,
               ex_syslogger: [k1: 3, k2: 4],
               backends: [:console]
             ]
    end

    test "with ex_syslogger, console and backends changes" do
      defaults = [
        logger: [
          ex_syslogger: [k1: 1, k2: 1],
          console: [k1: 2, k2: 2],
          backends: [:ex_syslogger, :console],
          key: 1
        ],
        pleroma: [key1: 1, key2: 2]
      ]

      logger =
        insert(:config,
          group: :logger,
          key: nil,
          value: [console: [k1: 4, k2: 4], k1: 3, k2: 4, backends: [:console]]
        )

      {[change], [pleroma: [key1: 1, key2: 2]]} =
        ConfigDB.reduce_defaults_and_merge_with_changes([logger], defaults)

      assert change.value == [
               ex_syslogger: [k1: 1, k2: 1],
               key: 1,
               console: [k1: 4, k2: 4],
               k1: 3,
               k2: 4,
               backends: [:console]
             ]
    end
  end

  test "all_with_db/0" do
    config = insert(:config)
    [change] = ConfigDB.all_with_db()
    assert change.db == Keyword.keys(config.value)
  end

  test "from_keyword_to_structs/2" do
    keyword = [
      pleroma: [
        key1: [k1: 1, k2: 1, k3: 1],
        key2: [k1: 2, k2: 2, k3: 2]
      ],
      logger: [k1: 3, k2: 3, ex_syslogger: [k1: 4, k2: 4], console: [k1: 5, k2: 5]]
    ]

    changes = ConfigDB.from_keyword_to_structs(keyword)

    Enum.each(changes, fn
      %{key: :key1} = change ->
        assert change.group == :pleroma
        assert change.value == [k1: 1, k2: 1, k3: 1]

      %{key: :key2} = change ->
        assert change.group == :pleroma
        assert change.value == [k1: 2, k2: 2, k3: 2]

      %{key: nil} = change ->
        assert change.group == :logger

        assert change.value == [
                 k1: 3,
                 k2: 3,
                 ex_syslogger: [k1: 4, k2: 4],
                 console: [k1: 5, k2: 5]
               ]
    end)
  end

  describe "merge_changes_with_defaults/2" do
    test "with existance changes" do
      defaults = [
        pleroma: [
          key1: [k1: 1, k2: 1, k3: 1],
          key2: [k1: 2, k2: 2, k3: 2]
        ],
        logger: [k1: 3, k2: 3]
      ]

      config1 = insert(:config, key: :key1, value: [k1: 4, k2: 4])
      config2 = insert(:config, key: :key2, value: [k1: 5, k2: 5])

      changes = ConfigDB.merge_changes_with_defaults([config1, config2], defaults)

      Enum.each(changes, fn
        %{key: :key1} = change -> assert change.value == [k3: 1, k1: 4, k2: 4]
        %{key: :key2} = change -> assert change.value == [k3: 2, k1: 5, k2: 5]
      end)
    end

    test "full subkey update and deep merge" do
      defaults = [
        pleroma: [
          assets: [
            mascots: [3, 4],
            subkey: [key1: [key: :val2, key2: :val2], key2: :val2],
            key: 5
          ]
        ]
      ]

      config =
        insert(:config,
          group: :pleroma,
          key: :assets,
          value: [mascots: [1, 2], subkey: [key1: [key: :val1, key2: :val1], key2: :val1]]
        )

      [merged] = ConfigDB.merge_changes_with_defaults([config], defaults)

      assert merged.value == [
               mascots: [1, 2],
               key: 5,
               subkey: [key1: [key: :val1, key2: :val1], key2: :val1]
             ]
    end

    test "merge for other subkeys" do
      defaults = [pleroma: [assets: [key: 5]]]

      config =
        insert(:config,
          group: :pleroma,
          key: :assets,
          value: [subkey: 3, default_mascot: :test_mascot]
        )

      [merged] = ConfigDB.merge_changes_with_defaults([config], defaults)
      assert merged.value == [key: 5, subkey: 3, default_mascot: :test_mascot]
    end

    test "with change deletion" do
      defaults = [pleroma: [assets: [key: 5]]]

      config =
        insert(:config,
          group: :pleroma,
          key: :assets,
          value: [subkey: 3, default_mascot: :test_mascot]
        )

      {:ok, config} = ConfigDB.delete(config)
      [merged] = ConfigDB.merge_changes_with_defaults([config], defaults)
      assert merged.value == [key: 5]
    end
  end
end
