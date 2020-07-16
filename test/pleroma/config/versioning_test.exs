# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Config.VersioningTest do
  use Pleroma.DataCase, async: true

  import Pleroma.Factory

  alias Pleroma.Config.Version
  alias Pleroma.Config.Versioning
  alias Pleroma.ConfigDB
  alias Pleroma.Repo

  @with_key %{
    group: :pleroma,
    key: :instance,
    value: [name: "Instance name"]
  }

  @without_key %{
    group: :quack,
    key: nil,
    value: [
      level: :warn,
      meta: [:all],
      webhook_url: "https://hooks.slack.com/services/YOUR-KEY-HERE"
    ]
  }

  @value_not_keyword %{
    group: :pleroma,
    key: Pleroma.Web.Auth.Authenticator,
    value: Pleroma.Web.Auth.PleromaAuthenticator
  }

  describe "new_version/1" do
    test "creates version" do
      changes = [@with_key, @without_key, @value_not_keyword]

      {:ok,
       %{
         :insert_version => version,
         :update_all_versions => {0, nil},
         {:insert_or_update, :pleroma, :instance} => _,
         {:insert_or_update, :quack, nil} => _
       }} = Versioning.new_version(changes)

      assert version.current
      assert backup_length(version) == 2

      assert version.backup[:quack] == @without_key[:value]

      assert version.backup[:pleroma][:instance] == @with_key[:value]

      assert version.backup[:pleroma][Pleroma.Web.Auth.Authenticator] ==
               @value_not_keyword[:value]

      assert Repo.aggregate(ConfigDB, :count) == 3
      assert Repo.aggregate(Version, :count) == 1
    end

    test "creates several versions" do
      change1 = [@with_key]

      {:ok,
       %{
         :insert_version => version1,
         :update_all_versions => {0, nil},
         {:insert_or_update, :pleroma, :instance} => _
       }} = Versioning.new_version(change1)

      change2 = [@without_key]

      {:ok,
       %{
         :insert_version => version2,
         :update_all_versions => {1, nil},
         {:insert_or_update, :quack, nil} => _
       }} = Versioning.new_version(change2)

      version1 = refresh_record(version1)
      refute version1.current

      assert backup_length(version1) == 1

      version2 = refresh_record(version2)
      assert version2.current

      assert backup_length(version2) == 2
    end

    test "error on empty list" do
      assert Versioning.new_version([]) == {:error, :empty_changes}
    end

    test "error on bad format" do
      assert Versioning.new_version(nil) == {:error, :bad_format}
    end

    test "process changes as single map" do
      {:ok,
       %{
         :insert_version => _,
         :update_all_versions => {0, nil},
         {:insert_or_update, :pleroma, :instance} => _
       }} = Versioning.new_version(@with_key)

      assert Repo.aggregate(ConfigDB, :count) == 1
    end

    test "error if value is not keyword" do
      assert Versioning.new_version([
               %{group: :pleroma, key: :key, value: %{}}
             ]) ==
               {:error, {:error, :pleroma, :key},
                {:value_must_be_keyword, %{group: :pleroma, key: :key, value: %{}}}, %{}}
    end

    test "error if value is list" do
      assert Versioning.new_version([
               %{group: :pleroma, key: :key, value: [1]}
             ]) ==
               {:error, {:error, :pleroma, :key},
                {:value_must_be_keyword, %{group: :pleroma, key: :key, value: [1]}}, %{}}
    end
  end

  describe "rollback/1" do
    test "bad steps format" do
      assert Versioning.rollback(nil) == {:error, :steps_format}
    end

    test "no versions" do
      assert Versioning.rollback() == {:error, :no_current_version}
    end

    test "rollback not possible, because there is only one version" do
      {:ok, _} = Versioning.new_version(@with_key)

      assert Versioning.rollback() == {:error, :rollback_not_possible}
    end

    test "rollbacks to previous version" do
      {:ok, _} = Versioning.new_version(@with_key)

      {:ok, _} = Versioning.new_version(@value_not_keyword)

      {:ok, _} = Versioning.new_version(@without_key)

      {:ok, _} = Versioning.rollback()

      configs = ConfigDB.all()

      Enum.each(configs, fn
        %{key: :instance} = config ->
          config.value == @with_key[:value]

        %{key: Pleroma.Web.Auth.Authenticator} = config ->
          config.value == @value_not_keyword[:value]
      end)

      assert Repo.aggregate(Version, :count) == 2

      version = Repo.get_by(Version, current: true)

      assert version.backup[:pleroma][:instance] == @with_key[:value]

      assert version.backup[:pleroma][Pleroma.Web.Auth.Authenticator] ==
               @value_not_keyword[:value]
    end

    test "rollbacks with 2 steps" do
      {:ok, _} = Versioning.new_version(@with_key)

      {:ok, _} = Versioning.new_version(@without_key)

      {:ok, _} =
        Versioning.new_version(%{
          group: :pleroma,
          key: :instance,
          value: [name: "New name"]
        })

      assert Repo.aggregate(ConfigDB, :count) == 2
      assert Repo.aggregate(Version, :count) == 3
      {:ok, _} = Versioning.rollback(2)

      assert Repo.aggregate(Version, :count) == 1

      [with_key] = ConfigDB.all()

      assert with_key.value == @with_key[:value]
    end

    test "rollbacks with 2 steps and creates new version for new change" do
      {:ok, _} = Versioning.new_version(@with_key)

      {:ok, _} = Versioning.new_version(@without_key)

      {:ok, _} =
        Versioning.new_version(%{
          group: :pleroma,
          key: :instance,
          value: [name: "New name"]
        })

      {:ok, _} = Versioning.rollback(2)

      {:ok, _} =
        Versioning.new_version(%{
          group: :pleroma,
          key: :instance,
          value: [name: "Last name"]
        })

      [with_key] = ConfigDB.all()
      assert with_key.value == [name: "Last name"]
    end

    test "properly rollbacks with settings without keys" do
      {:ok, _} = Versioning.new_version(@with_key)

      {:ok, _} = Versioning.new_version(@without_key)

      {:ok, _} =
        Versioning.new_version(%{
          group: :pleroma,
          key: :instance,
          value: [name: "New name"]
        })

      {:ok, _} = Versioning.rollback()

      config = ConfigDB.get_by_params(%{group: :quack})
      assert config.value == @without_key[:value]
    end

    test "properly rollbacks with logger settings" do
      {:ok, _} = Versioning.new_version(@with_key)

      {:ok, _} =
        Versioning.new_version([
          %{
            group: :logger,
            value: [
              console: [
                level: :debug,
                format: "\n$time $metadata[$level] $message\n",
                metadata: [:request_id]
              ],
              backends: [:console]
            ]
          }
        ])

      {:ok, _} = Versioning.new_version(@without_key)

      {:ok, _} = Versioning.rollback()

      logger = ConfigDB.get_by_params(%{group: :logger})

      assert logger.value == [
               console: [
                 level: :debug,
                 format: "\n$time $metadata[$level] $message\n",
                 metadata: [:request_id]
               ],
               backends: [:console]
             ]
    end
  end

  describe "migrate/1" do
    test "migrates settings from config file" do
      {:ok, _} = Versioning.migrate("test/fixtures/config/temp.secret.exs")

      assert Repo.aggregate(ConfigDB, :count) == 3

      config1 = ConfigDB.get_by_params(%{group: :pleroma, key: :first_setting})
      config2 = ConfigDB.get_by_params(%{group: :pleroma, key: :second_setting})
      config3 = ConfigDB.get_by_params(%{group: :quack})

      assert config1.value == [key: "value", key2: [Repo]]
      assert config2.value == [key: "value2", key2: ["Activity"]]
      assert config3.value == [level: :info]

      [version] = Repo.all(Version)

      assert version.backup == [
               pleroma: [
                 second_setting: [key: "value2", key2: ["Activity"]],
                 first_setting: [key: "value", key2: [Repo]]
               ],
               quack: [level: :info]
             ]
    end

    test "truncates table on migration" do
      insert_list(4, :config)

      assert Repo.aggregate(ConfigDB, :count) == 4

      {:ok, _} = Versioning.migrate("test/fixtures/config/temp.secret.exs")

      assert Repo.aggregate(ConfigDB, :count) == 3
    end
  end

  describe "migrate_namespace/2" do
    test "common namespace rename" do
      value_before_migration = [name: "Name"]

      {:ok, %{:insert_version => version1}} =
        Versioning.new_version(%{
          group: :pleroma,
          key: :key1,
          value: value_before_migration
        })

      {:ok, %{:insert_version => version2}} =
        Versioning.new_version(%{
          group: :pleroma,
          key: :key2,
          value: [name: "Name"]
        })

      {:ok, %{:insert_version => version3}} =
        Versioning.new_version(%{
          group: :pleroma,
          key: :key3,
          value: [name: "Name"]
        })

      {:ok, _} = Versioning.migrate_namespace({:pleroma, :key1}, {:ex_aws, :new_key})

      version1 = refresh_record(version1)
      assert version1.backup == [ex_aws: [new_key: [name: "Name"]]]
      version2 = refresh_record(version2)

      assert version2.backup == [
               ex_aws: [new_key: [name: "Name"]],
               pleroma: [key2: [name: "Name"]]
             ]

      version3 = refresh_record(version3)

      assert version3.backup == [
               ex_aws: [new_key: [name: "Name"]],
               pleroma: [key2: [name: "Name"], key3: [name: "Name"]]
             ]

      assert Repo.aggregate(from(c in ConfigDB, where: c.group == ^:pleroma), :count, :id) == 2
      config = ConfigDB.get_by_params(%{group: :ex_aws, key: :new_key})
      assert config.value == value_before_migration

      {:ok, _} = Versioning.migrate_namespace({:pleroma, :key2}, {:pleroma, :new_key})

      version1 = refresh_record(version1)
      assert version1.backup == [ex_aws: [new_key: [name: "Name"]]]
      version2 = refresh_record(version2)

      assert version2.backup == [
               pleroma: [new_key: [name: "Name"]],
               ex_aws: [new_key: [name: "Name"]]
             ]

      version3 = refresh_record(version3)

      assert version3.backup == [
               ex_aws: [new_key: [name: "Name"]],
               pleroma: [new_key: [name: "Name"], key3: [name: "Name"]]
             ]
    end

    test "old namespace exists in old backups" do
      {:ok, %{:insert_version => version1}} =
        Versioning.new_version(%{
          group: :pleroma,
          key: :key1,
          value: [name: "Name"]
        })

      {:ok, %{:insert_version => version2}} =
        Versioning.new_version([
          %{
            group: :pleroma,
            key: :key2,
            value: [name: "Name"]
          },
          %{group: :pleroma, key: :key1, delete: true}
        ])

      {:ok, _} = Versioning.migrate_namespace({:pleroma, :key1}, {:ex_aws, :new_key})

      version1 = refresh_record(version1)
      assert version1.backup == [ex_aws: [new_key: [name: "Name"]]]
      version2 = refresh_record(version2)

      assert version2.backup == [
               pleroma: [key2: [name: "Name"]]
             ]

      assert Repo.aggregate(from(c in ConfigDB, where: c.group == ^:pleroma), :count, :id) == 1
      refute ConfigDB.get_by_params(%{group: :ex_aws, key: :new_key})
    end
  end

  defp backup_length(%{backup: backup}) do
    backup
    |> Keyword.keys()
    |> length()
  end
end
