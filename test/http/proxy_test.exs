# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP.ProxyTest do
  use ExUnit.Case, async: true
  use Pleroma.Tests.Helpers

  import ExUnit.CaptureLog

  alias Pleroma.HTTP.Proxy

  describe "parse_proxy/1" do
    test "ip with port" do
      assert Proxy.parse_proxy("127.0.0.1:8123") == {:ok, {127, 0, 0, 1}, 8123}
    end

    test "host with port" do
      assert Proxy.parse_proxy("localhost:8123") == {:ok, 'localhost', 8123}
    end

    test "as tuple" do
      assert Proxy.parse_proxy({:socks4, :localhost, 9050}) ==
               {:ok, :socks4, 'localhost', 9050}
    end

    test "as tuple with string host" do
      assert Proxy.parse_proxy({:socks5, "localhost", 9050}) ==
               {:ok, :socks5, 'localhost', 9050}
    end
  end

  describe "parse_proxy/1 errors" do
    test "ip without port" do
      capture_log(fn ->
        assert Proxy.parse_proxy("127.0.0.1") == {:error, :invalid_proxy}
      end) =~ "parsing proxy fail \"127.0.0.1\""
    end

    test "host without port" do
      capture_log(fn ->
        assert Proxy.parse_proxy("localhost") == {:error, :invalid_proxy}
      end) =~ "parsing proxy fail \"localhost\""
    end

    test "host with bad port" do
      capture_log(fn ->
        assert Proxy.parse_proxy("localhost:port") == {:error, :invalid_proxy_port}
      end) =~ "parsing port in proxy fail \"localhost:port\""
    end

    test "ip with bad port" do
      capture_log(fn ->
        assert Proxy.parse_proxy("127.0.0.1:15.9") == {:error, :invalid_proxy_port}
      end) =~ "parsing port in proxy fail \"127.0.0.1:15.9\""
    end

    test "as tuple without port" do
      capture_log(fn ->
        assert Proxy.parse_proxy({:socks5, :localhost}) == {:error, :invalid_proxy}
      end) =~ "parsing proxy fail {:socks5, :localhost}"
    end

    test "with nil" do
      assert Proxy.parse_proxy(nil) == nil
    end
  end

  describe "maybe_add_proxy/1" do
    test "proxy as ip with port" do
      clear_config([:http, :proxy_url], "127.0.0.1:8123")

      assert Proxy.maybe_add_proxy([]) == [proxy: {{127, 0, 0, 1}, 8123}]
    end

    test "proxy as localhost with port" do
      clear_config([:http, :proxy_url], "localhost:8123")
      assert Proxy.maybe_add_proxy([]) == [proxy: {'localhost', 8123}]
    end

    test "proxy as tuple" do
      clear_config([:http, :proxy_url], {:socks4, :localhost, 9050})
      assert Proxy.maybe_add_proxy([]) == [proxy: {:socks4, 'localhost', 9050}]
    end

    test "without proxy" do
      assert Proxy.maybe_add_proxy([]) == []
    end
  end
end
