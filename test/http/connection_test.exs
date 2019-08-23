defmodule Pleroma.HTTP.ConnectionTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias Pleroma.HTTP.Connection

  describe "parse_host/1" do
    test "as atom" do
      assert Connection.parse_host(:localhost) == 'localhost'
    end

    test "as string" do
      assert Connection.parse_host("localhost.com") == 'localhost.com'
    end

    test "as string ip" do
      assert Connection.parse_host("127.0.0.1") == {127, 0, 0, 1}
    end
  end

  describe "parse_proxy/1" do
    test "ip with port" do
      assert Connection.parse_proxy("127.0.0.1:8123") == {:ok, {127, 0, 0, 1}, 8123}
    end

    test "host with port" do
      assert Connection.parse_proxy("localhost:8123") == {:ok, 'localhost', 8123}
    end

    test "as tuple" do
      assert Connection.parse_proxy({:socks5, :localhost, 9050}) == {:ok, 'localhost', 9050}
    end

    test "as tuple with string host" do
      assert Connection.parse_proxy({:socks5, "localhost", 9050}) == {:ok, 'localhost', 9050}
    end

    test "ip without port" do
      capture_log(fn ->
        assert Connection.parse_proxy("127.0.0.1") == {:error, :error_parsing_proxy}
      end) =~ "parsing proxy fail \"127.0.0.1\""
    end

    test "host without port" do
      capture_log(fn ->
        assert Connection.parse_proxy("localhost") == {:error, :error_parsing_proxy}
      end) =~ "parsing proxy fail \"localhost\""
    end

    test "host with bad port" do
      capture_log(fn ->
        assert Connection.parse_proxy("localhost:port") == {:error, :error_parsing_port_in_proxy}
      end) =~ "parsing port in proxy fail \"localhost:port\""
    end

    test "as tuple without port" do
      capture_log(fn ->
        assert Connection.parse_proxy({:socks5, :localhost}) == {:error, :error_parsing_proxy}
      end) =~ "parsing proxy fail {:socks5, :localhost}"
    end

    test "with nil" do
      assert Connection.parse_proxy(nil) == nil
    end
  end
end
