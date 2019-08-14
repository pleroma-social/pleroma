# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Gun.ConnectionsTest do
  use ExUnit.Case
  alias Pleroma.Gun.{Connections, Conn, API}

  setup do
    name = :test_gun_connections
    adapter = Application.get_env(:tesla, :adapter)
    Application.put_env(:tesla, :adapter, Tesla.Adapter.Gun)
    on_exit(fn -> Application.put_env(:tesla, :adapter, adapter) end)
    {:ok, pid} = Connections.start_link(name)

    {:ok, name: name, pid: pid}
  end

  describe "alive?/2" do
    test "is alive", %{name: name} do
      assert Connections.alive?(name)
    end

    test "returns false if not started" do
      refute Connections.alive?(:some_random_name)
    end
  end

  test "try_to_get_gun_conn/1 returns conn", %{name: name, pid: pid} do
    conn = Connections.try_to_get_gun_conn("http://some-domain.com", [genserver_pid: pid], name)
    assert is_pid(conn)
    assert Process.alive?(conn)

    reused_conn = Connections.get_conn("http://some-domain.com", [genserver_pid: pid], name)

    assert conn == reused_conn

    %Connections{
      conns: %{
        "some-domain.com:80" => %Conn{
          conn: ^conn,
          state: :up,
          waiting_pids: []
        }
      }
    } = Connections.get_state(name)
  end

  test "opens connection and reuse it on next request", %{name: name, pid: pid} do
    conn = Connections.get_conn("http://some-domain.com", [genserver_pid: pid], name)

    assert is_pid(conn)
    assert Process.alive?(conn)

    reused_conn = Connections.get_conn("http://some-domain.com", [genserver_pid: pid], name)

    assert conn == reused_conn

    %Connections{
      conns: %{
        "some-domain.com:80" => %Conn{
          conn: ^conn,
          state: :up,
          waiting_pids: []
        }
      }
    } = Connections.get_state(name)
  end

  test "reuses connection based on protocol", %{name: name, pid: pid} do
    conn = Connections.get_conn("http://some-domain.com", [genserver_pid: pid], name)
    assert is_pid(conn)
    assert Process.alive?(conn)

    https_conn = Connections.get_conn("https://some-domain.com", [genserver_pid: pid], name)

    refute conn == https_conn

    reused_https = Connections.get_conn("https://some-domain.com", [genserver_pid: pid], name)

    refute conn == reused_https

    assert reused_https == https_conn

    %Connections{
      conns: %{
        "some-domain.com:80" => %Conn{
          conn: ^conn,
          state: :up,
          waiting_pids: []
        },
        "some-domain.com:443" => %Conn{
          conn: ^https_conn,
          state: :up,
          waiting_pids: []
        }
      }
    } = Connections.get_state(name)
  end

  test "process gun_down message", %{name: name, pid: pid} do
    conn = Connections.get_conn("http://gun_down.com", [genserver_pid: pid], name)

    refute conn

    %Connections{
      conns: %{
        "gun_down.com:80" => %Conn{
          conn: _,
          state: :down,
          waiting_pids: _
        }
      }
    } = Connections.get_state(name)
  end

  test "process gun_down message and then gun_up", %{name: name, pid: pid} do
    conn = Connections.get_conn("http://gun_down_and_up.com", [genserver_pid: pid], name)

    refute conn

    %Connections{
      conns: %{
        "gun_down_and_up.com:80" => %Conn{
          conn: _,
          state: :down,
          waiting_pids: _
        }
      }
    } = Connections.get_state(name)

    conn = Connections.get_conn("http://gun_down_and_up.com", [genserver_pid: pid], name)

    assert is_pid(conn)
    assert Process.alive?(conn)

    %Connections{
      conns: %{
        "gun_down_and_up.com:80" => %Conn{
          conn: _,
          state: :up,
          waiting_pids: []
        }
      }
    } = Connections.get_state(name)
  end

  test "async processes get same conn for same domain", %{name: name, pid: pid} do
    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          Connections.get_conn("http://some-domain.com", [genserver_pid: pid], name)
        end)
      end

    tasks_with_results = Task.yield_many(tasks)

    results =
      Enum.map(tasks_with_results, fn {task, res} ->
        res || Task.shutdown(task, :brutal_kill)
      end)

    conns = for {:ok, value} <- results, do: value

    %Connections{
      conns: %{
        "some-domain.com:80" => %Conn{
          conn: conn,
          state: :up,
          waiting_pids: []
        }
      }
    } = Connections.get_state(name)

    assert Enum.all?(conns, fn res -> res == conn end)
  end

  describe "integration test" do
    @describetag :integration

    test "opens connection and reuse it on next request", %{name: name} do
      api = Pleroma.Config.get([API])
      Pleroma.Config.put([API], :gun)
      on_exit(fn -> Pleroma.Config.put([API], api) end)
      conn = Connections.get_conn("http://httpbin.org", [], name)

      assert is_pid(conn)
      assert Process.alive?(conn)

      reused_conn = Connections.get_conn("http://httpbin.org", [], name)

      assert conn == reused_conn

      %Connections{
        conns: %{
          "httpbin.org:80" => %Conn{
            conn: ^conn,
            state: :up,
            waiting_pids: []
          }
        }
      } = Connections.get_state(name)
    end
  end
end
