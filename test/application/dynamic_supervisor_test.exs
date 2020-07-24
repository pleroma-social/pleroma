defmodule Pleroma.Application.DependenciesSupervisorTest do
  use ExUnit.Case
  use Pleroma.Tests.Helpers

  import ExUnit.CaptureLog

  alias Pleroma.Application.DependenciesState
  alias Pleroma.Application.DependenciesSupervisor

  defp update_relations(new_relations) do
    relations = Pleroma.Config.get(:config_relations)

    relations = Enum.reduce(new_relations, relations, fn relation, acc -> [relation | acc] end)

    Pleroma.Config.put(:config_relations, relations)
  end

  setup do: clear_config(:config_relations)

  test "starts and restart dynamic childs" do
    path1 = {:pleroma, :dummy_module1}
    path2 = {:pleroma, :dummy_module2, [:subkey]}
    path3 = {:pleroma, :dummy_module3}
    module1 = Pleroma.DummyModule1
    module2 = Pleroma.DummyModule2

    update_relations([{path1, module1}, {path2, module2}, {path3, module1}])

    DependenciesSupervisor.start_children([module1, module2], :dynamic)
    pid1 = Process.whereis(module1)
    pid2 = Process.whereis(module2)

    # all relations where saved in state
    assert DependenciesState.pid(path1) == pid1
    assert DependenciesState.pid(path2) == pid2
    assert DependenciesState.pid(path3) == pid1

    refute DependenciesSupervisor.need_reboot?()
    # config was changed only for 2 paths
    DependenciesSupervisor.put_paths([path1, path2])

    assert DependenciesSupervisor.need_reboot?()
    # check that only changed paths are in state
    paths = DependenciesState.paths()
    assert path1 in paths
    assert path2 in paths
    refute path3 in paths

    DependenciesSupervisor.restart_children()

    # check that pids for dummy modules were updated and saved correctly after restart
    refute DependenciesState.pid(path1) == pid1
    refute DependenciesState.pid(path2) == pid2
    refute DependenciesState.pid(path3) == pid1

    pid1 = Process.whereis(module1)
    pid2 = Process.whereis(module2)

    # check that pid for path3 was updated too
    assert DependenciesState.pid(path1) == pid1
    assert DependenciesState.pid(path2) == pid2
    assert DependenciesState.pid(path3) == pid1

    assert DynamicSupervisor.terminate_child(DependenciesSupervisor, pid1) ==
             :ok

    assert DynamicSupervisor.terminate_child(DependenciesSupervisor, pid2) ==
             :ok

    Enum.each([path1, path2, path3], &DependenciesState.delete_pid/1)
  end

  test "if static child is configured to be ignored" do
    assert DependenciesSupervisor.start_children(
             [Pleroma.DummyModule3],
             :static
           ) ==
             :ok
  end

  test "dynamic child is ignored on restart" do
    path = {:pleroma, :dummy_module3}
    update_relations([{path, Pleroma.DummyModule3}])
    DependenciesSupervisor.put_paths([path])
    assert DependenciesSupervisor.restart_children() == :ok
    assert DependenciesState.get_and_reset_paths() == []
  end

  test "error if child was already started" do
    path = {:pleroma, :dummy_module1}
    module = Pleroma.DummyModule1
    update_relations([{path, module}])

    capture_log(fn ->
      assert {:error, {:already_started, _}} =
               DependenciesSupervisor.start_children(
                 [
                   module,
                   module
                 ],
                 :dynamic
               )
    end) =~ "{:error, {:already_started"

    pid = Process.whereis(module)

    assert DynamicSupervisor.terminate_child(DependenciesSupervisor, pid) ==
             :ok

    DependenciesState.delete_pid(path)
    DependenciesSupervisor.put_paths([])
  end

  test "restart for child, which wasn't started yet" do
    path = {:pleroma, :dummy_module1}
    module = Pleroma.DummyModule1
    update_relations([{path, module}])

    DependenciesSupervisor.put_paths([path])

    assert DependenciesSupervisor.restart_children() == :ok

    pid = Process.whereis(module)

    assert DynamicSupervisor.terminate_child(DependenciesSupervisor, pid) ==
             :ok

    DependenciesState.delete_pid(path)
  end

  test "restart child, which crashed and update Agent" do
    path = {:pleroma, :dummy_module1}
    module = Pleroma.DummyModule1

    update_relations([{path, module}])

    DependenciesSupervisor.start_children([module], :dynamic)

    pid = Process.whereis(module)

    DependenciesSupervisor.put_paths([path])

    Process.exit(pid, :kill)
    Process.sleep(5)
    pid_after_crash = Process.whereis(module)
    refute pid == pid_after_crash
    # State wasn't updated yet, so it's normal
    assert DependenciesState.pid(path) == pid
    assert DependenciesSupervisor.restart_children() == :ok

    updated_pid = Process.whereis(module)
    refute updated_pid == pid_after_crash

    assert DependenciesState.pid(path) == updated_pid

    assert DynamicSupervisor.terminate_child(
             DependenciesSupervisor,
             updated_pid
           ) ==
             :ok

    DependenciesState.delete_pid(path)
  end

  test "restart by path without child" do
    path = {:pleroma, :dummy_module1}
    module = Pleroma.DummyModule1
    update_relations([{path, module}])
    assert DependenciesSupervisor.restart_children() == :ok
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
    Agent.start_link(fn -> nil end, name: __MODULE__)
  end
end

defmodule Pleroma.DummyModule3 do
  use Agent

  def start_link(_), do: :ignore
end
