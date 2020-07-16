# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.ConfigDependentDepsTest do
  use ExUnit.Case

  alias Pleroma.Application.ConfigDependentDeps

  setup do
    {:ok, _} =
      DynamicSupervisor.start_link(
        strategy: :one_for_one,
        name: Pleroma.Application.DynamicSupervisorTest
      )

    {:ok, pid} =
      Pleroma.Application.ConfigDependentDeps.start_link(
        dynamic_supervisor: Pleroma.Application.DynamicSupervisorTest,
        name: Pleroma.Application.ConfigDependentDepsTesting,
        relations: [
          {{:pleroma, :dummy_module1}, Pleroma.DummyModule1},
          {{:pleroma, :dummy_module2}, Pleroma.DummyModule2},
          {:dummy_group1, :dummy_group1},
          {:ex_aws, :ex_aws},
          {:not_started_app, :not_started_app}
        ]
      )

    [pid: pid]
  end

  test "start_dependency/2", %{pid: pid} do
    {:ok, pid} = ConfigDependentDeps.start_dependency(Pleroma.DummyModule1, pid)
    assert Process.alive?(pid)
  end

  describe "need_reboot?/1" do
    test "apps and paths", %{pid: pid} do
      changes = [
        %Pleroma.ConfigDB{group: :dummy_group1},
        %Pleroma.ConfigDB{group: :pleroma, key: :dummy_module1}
      ]

      assert ConfigDependentDeps.save_config_paths_for_restart(changes, pid) == [
               {:pleroma, :dummy_module1},
               :dummy_group1
             ]

      assert ConfigDependentDeps.need_reboot?(pid)
    end

    test "app and path are not duplicated", %{pid: pid} do
      changes = [
        %Pleroma.ConfigDB{group: :dummy_group1},
        %Pleroma.ConfigDB{group: :dummy_group1},
        %Pleroma.ConfigDB{group: :pleroma, key: :dummy_module1},
        %Pleroma.ConfigDB{group: :pleroma, key: :dummy_module1}
      ]

      assert ConfigDependentDeps.save_config_paths_for_restart(changes, pid) == [
               {:pleroma, :dummy_module1},
               :dummy_group1
             ]

      assert ConfigDependentDeps.need_reboot?(pid)
    end
  end

  describe "restart_dependencies/1" do
    test "started dependency", %{pid: pid} do
      {:ok, dummy_pid} = ConfigDependentDeps.start_dependency(Pleroma.DummyModule1, pid)

      changes = [
        %Pleroma.ConfigDB{group: :ex_aws},
        %Pleroma.ConfigDB{group: :pleroma, key: :dummy_module1}
      ]

      assert ConfigDependentDeps.save_config_paths_for_restart(changes, pid) == [
               {:pleroma, :dummy_module1},
               :ex_aws
             ]

      assert :ok == ConfigDependentDeps.restart_dependencies(pid)

      restarted = Process.whereis(Pleroma.DummyModule1)

      refute dummy_pid == restarted
    end

    test "not started process and app", %{pid: pid} do
      changes = [
        %Pleroma.ConfigDB{group: :pleroma, key: :dummy_module1},
        %Pleroma.ConfigDB{group: :not_started_app}
      ]

      assert ConfigDependentDeps.save_config_paths_for_restart(changes, pid) == [
               :not_started_app,
               {:pleroma, :dummy_module1}
             ]

      assert :ok == ConfigDependentDeps.restart_dependencies(pid)

      started = Process.whereis(Pleroma.DummyModule1)

      assert Process.alive?(started)
    end

    test "ignored dependency", %{pid: pid} do
      changes = [
        %Pleroma.ConfigDB{group: :pleroma, key: :dummy_module2}
      ]

      assert ConfigDependentDeps.save_config_paths_for_restart(changes, pid) == [
               {:pleroma, :dummy_module2}
             ]

      assert :ok == ConfigDependentDeps.restart_dependencies(pid)

      refute Process.whereis(Pleroma.DummyModule2)
    end
  end

  test "process goes down", %{pid: pid} do
    {:ok, dummy_pid} = ConfigDependentDeps.start_dependency(Pleroma.DummyModule1, pid)

    Process.exit(dummy_pid, :kill)

    Process.sleep(10)
    restarted = Process.whereis(Pleroma.DummyModule1)
    refute restarted == dummy_pid
  end
end

defmodule Pleroma.DummyModule1 do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> nil end, name: __MODULE__)
  end
end

defmodule Pleroma.DummyModule2 do
  use Agent

  def start_link(_) do
    :ignore
  end
end
