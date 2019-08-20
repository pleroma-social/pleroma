# Pleroma: A lightweight social networking server
# Copyright © 2017-2018 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTPTest do
  use Pleroma.DataCase
  import Tesla.Mock

  setup do
    mock(fn
      %{
        method: :get,
        url: "http://example.com/hello",
        headers: [{"content-type", "application/json"}]
      } ->
        json(%{"my" => "data"})

      %{method: :get, url: "http://example.com/hello"} ->
        %Tesla.Env{status: 200, body: "hello"}

      %{method: :post, url: "http://example.com/world"} ->
        %Tesla.Env{status: 200, body: "world"}
    end)

    :ok
  end

  describe "get/1" do
    test "returns successfully result" do
      assert Pleroma.HTTP.get("http://example.com/hello") == {
               :ok,
               %Tesla.Env{status: 200, body: "hello"}
             }
    end
  end

  describe "get/2 (with headers)" do
    test "returns successfully result for json content-type" do
      assert Pleroma.HTTP.get("http://example.com/hello", [{"content-type", "application/json"}]) ==
               {
                 :ok,
                 %Tesla.Env{
                   status: 200,
                   body: "{\"my\":\"data\"}",
                   headers: [{"content-type", "application/json"}]
                 }
               }
    end
  end

  describe "post/2" do
    test "returns successfully result" do
      assert Pleroma.HTTP.post("http://example.com/world", "") == {
               :ok,
               %Tesla.Env{status: 200, body: "world"}
             }
    end
  end

  @tag :integration
  test "get_conn_for_gun/3" do
    adapter = Application.get_env(:tesla, :adapter)
    Application.put_env(:tesla, :adapter, Tesla.Adapter.Gun)
    api = Pleroma.Config.get([Pleroma.Gun.API])
    Pleroma.Config.put([Pleroma.Gun.API], Pleroma.Gun.API.Gun)

    on_exit(fn ->
      Application.put_env(:tesla, :adapter, adapter)
      Pleroma.Config.put([Pleroma.Gun.API], api)
    end)

    options = [adapter: [pool: :federation]]

    assert {:ok, resp} =
             Pleroma.HTTP.request(:get, "https://httpbin.org/user-agent", "", [], options)

    adapter_opts = resp.opts[:adapter]

    assert adapter_opts[:original] == "httpbin.org:443"
    refute adapter_opts[:close_conn]
    assert adapter_opts[:pool] == :federation
  end
end
