# # Pleroma: A lightweight social networking server
# # Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# # SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.Agent do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> %{reboot_paths: [], pids: %{}} end, name: __MODULE__)
  end

  @spec pid(any()) :: pid()
  def pid(key) do
    Agent.get(__MODULE__, fn state -> state[:pids][key] end)
  end

  @spec put_pid(any(), pid()) :: :ok
  def put_pid(key, pid) do
    Agent.update(__MODULE__, fn state -> put_in(state, [:pids, key], pid) end)
  end

  @spec delete_pid(any()) :: :ok
  def delete_pid(key) do
    Agent.update(__MODULE__, fn state -> put_in(state[:pids], Map.delete(state[:pids], key)) end)
  end

  @spec put_paths([any()]) :: :ok
  def put_paths(paths) do
    Agent.update(__MODULE__, fn state ->
      put_in(state[:reboot_paths], Enum.uniq(state[:reboot_paths] ++ paths))
    end)
  end

  @spec get_and_reset_paths() :: [any()]
  def get_and_reset_paths do
    Agent.get_and_update(__MODULE__, fn state ->
      {state[:reboot_paths], put_in(state[:reboot_paths], [])}
    end)
  end

  @spec paths() :: [any()]
  def paths do
    Agent.get(__MODULE__, fn state -> state[:reboot_paths] end)
  end
end
