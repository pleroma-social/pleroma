# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Config.ConverterTest do
  use ExUnit.Case, async: true

  alias Pleroma.Config.Converter

  describe "to_elixir_types/1" do
    test "string" do
      assert Converter.to_elixir_types("value as string") == "value as string"
    end

    test "boolean" do
      assert Converter.to_elixir_types(false) == false
    end

    test "nil" do
      assert Converter.to_elixir_types(nil) == nil
    end

    test "integer" do
      assert Converter.to_elixir_types(150) == 150
    end

    test "atom" do
      assert Converter.to_elixir_types(":atom") == :atom
    end

    test "ssl options" do
      assert Converter.to_elixir_types([":tlsv1", ":tlsv1.1", ":tlsv1.2"]) == [
               :tlsv1,
               :"tlsv1.1",
               :"tlsv1.2"
             ]
    end

    test "pleroma module" do
      assert Converter.to_elixir_types("Pleroma.Bookmark") == Pleroma.Bookmark
    end

    test "pleroma string" do
      assert Converter.to_elixir_types("Pleroma") == "Pleroma"
    end

    test "phoenix module" do
      assert Converter.to_elixir_types("Phoenix.Socket.V1.JSONSerializer") ==
               Phoenix.Socket.V1.JSONSerializer
    end

    test "tesla module" do
      assert Converter.to_elixir_types("Tesla.Adapter.Hackney") == Tesla.Adapter.Hackney
    end

    test "ExSyslogger module" do
      assert Converter.to_elixir_types("ExSyslogger") == ExSyslogger
    end

    test "Quack.Logger module" do
      assert Converter.to_elixir_types("Quack.Logger") == Quack.Logger
    end

    test "Swoosh.Adapters modules" do
      assert Converter.to_elixir_types("Swoosh.Adapters.SMTP") == Swoosh.Adapters.SMTP
      assert Converter.to_elixir_types("Swoosh.Adapters.AmazonSES") == Swoosh.Adapters.AmazonSES
    end

    test "sigil" do
      assert Converter.to_elixir_types("~r[comp[lL][aA][iI][nN]er]") == ~r/comp[lL][aA][iI][nN]er/
    end

    test "link sigil" do
      assert Converter.to_elixir_types("~r/https:\/\/example.com/") == ~r/https:\/\/example.com/
    end

    test "link sigil with um modifiers" do
      assert Converter.to_elixir_types("~r/https:\/\/example.com/um") ==
               ~r/https:\/\/example.com/um
    end

    test "link sigil with i modifier" do
      assert Converter.to_elixir_types("~r/https:\/\/example.com/i") == ~r/https:\/\/example.com/i
    end

    test "link sigil with s modifier" do
      assert Converter.to_elixir_types("~r/https:\/\/example.com/s") == ~r/https:\/\/example.com/s
    end

    test "raise if valid delimiter not found" do
      assert_raise ArgumentError, "valid delimiter for Regex expression not found", fn ->
        Converter.to_elixir_types("~r/https://[]{}<>\"'()|example.com/s")
      end
    end

    test "2 child tuple" do
      assert Converter.to_elixir_types(%{"tuple" => ["v1", ":v2"]}) == {"v1", :v2}
    end

    test "proxy tuple with localhost" do
      assert Converter.to_elixir_types(%{
               "tuple" => [":proxy_url", %{"tuple" => [":socks5", "localhost", 1234]}]
             }) == {:proxy_url, {:socks5, :localhost, 1234}}
    end

    test "proxy tuple with domain" do
      assert Converter.to_elixir_types(%{
               "tuple" => [":proxy_url", %{"tuple" => [":socks5", "domain.com", 1234]}]
             }) == {:proxy_url, {:socks5, 'domain.com', 1234}}
    end

    test "proxy tuple with ip" do
      assert Converter.to_elixir_types(%{
               "tuple" => [":proxy_url", %{"tuple" => [":socks5", "127.0.0.1", 1234]}]
             }) == {:proxy_url, {:socks5, {127, 0, 0, 1}, 1234}}
    end

    test "tuple with n childs" do
      assert Converter.to_elixir_types(%{
               "tuple" => [
                 "v1",
                 ":v2",
                 "Pleroma.Bookmark",
                 150,
                 false,
                 "Phoenix.Socket.V1.JSONSerializer"
               ]
             }) == {"v1", :v2, Pleroma.Bookmark, 150, false, Phoenix.Socket.V1.JSONSerializer}
    end

    test "map with string key" do
      assert Converter.to_elixir_types(%{"key" => "value"}) == %{"key" => "value"}
    end

    test "map with atom key" do
      assert Converter.to_elixir_types(%{":key" => "value"}) == %{key: "value"}
    end

    test "list of strings" do
      assert Converter.to_elixir_types(["v1", "v2", "v3"]) == ["v1", "v2", "v3"]
    end

    test "list of modules" do
      assert Converter.to_elixir_types(["Pleroma.Repo", "Pleroma.Activity"]) == [
               Pleroma.Repo,
               Pleroma.Activity
             ]
    end

    test "list of atoms" do
      assert Converter.to_elixir_types([":v1", ":v2", ":v3"]) == [:v1, :v2, :v3]
    end

    test "list of mixed values" do
      assert Converter.to_elixir_types([
               "v1",
               ":v2",
               "Pleroma.Repo",
               "Phoenix.Socket.V1.JSONSerializer",
               15,
               false
             ]) == [
               "v1",
               :v2,
               Pleroma.Repo,
               Phoenix.Socket.V1.JSONSerializer,
               15,
               false
             ]
    end

    test "simple keyword" do
      assert Converter.to_elixir_types([%{"tuple" => [":key", "value"]}]) == [key: "value"]
    end

    test "keyword" do
      assert Converter.to_elixir_types([
               %{"tuple" => [":types", "Pleroma.PostgresTypes"]},
               %{"tuple" => [":telemetry_event", ["Pleroma.Repo.Instrumenter"]]},
               %{"tuple" => [":migration_lock", nil]},
               %{"tuple" => [":key1", 150]},
               %{"tuple" => [":key2", "string"]}
             ]) == [
               types: Pleroma.PostgresTypes,
               telemetry_event: [Pleroma.Repo.Instrumenter],
               migration_lock: nil,
               key1: 150,
               key2: "string"
             ]
    end

    test "trandformed keyword" do
      assert Converter.to_elixir_types(a: 1, b: 2, c: "string") == [a: 1, b: 2, c: "string"]
    end

    test "complex keyword with nested mixed childs" do
      assert Converter.to_elixir_types([
               %{"tuple" => [":uploader", "Pleroma.Uploaders.Local"]},
               %{"tuple" => [":filters", ["Pleroma.Upload.Filter.Dedupe"]]},
               %{"tuple" => [":link_name", true]},
               %{"tuple" => [":proxy_remote", false]},
               %{"tuple" => [":common_map", %{":key" => "value"}]},
               %{
                 "tuple" => [
                   ":proxy_opts",
                   [
                     %{"tuple" => [":redirect_on_failure", false]},
                     %{"tuple" => [":max_body_length", 1_048_576]},
                     %{
                       "tuple" => [
                         ":http",
                         [
                           %{"tuple" => [":follow_redirect", true]},
                           %{"tuple" => [":pool", ":upload"]}
                         ]
                       ]
                     }
                   ]
                 ]
               }
             ]) == [
               uploader: Pleroma.Uploaders.Local,
               filters: [Pleroma.Upload.Filter.Dedupe],
               link_name: true,
               proxy_remote: false,
               common_map: %{key: "value"},
               proxy_opts: [
                 redirect_on_failure: false,
                 max_body_length: 1_048_576,
                 http: [
                   follow_redirect: true,
                   pool: :upload
                 ]
               ]
             ]
    end

    test "common keyword" do
      assert Converter.to_elixir_types([
               %{"tuple" => [":level", ":warn"]},
               %{"tuple" => [":meta", [":all"]]},
               %{"tuple" => [":path", ""]},
               %{"tuple" => [":val", nil]},
               %{"tuple" => [":webhook_url", "https://hooks.slack.com/services/YOUR-KEY-HERE"]}
             ]) == [
               level: :warn,
               meta: [:all],
               path: "",
               val: nil,
               webhook_url: "https://hooks.slack.com/services/YOUR-KEY-HERE"
             ]
    end

    test "complex keyword with sigil" do
      assert Converter.to_elixir_types([
               %{"tuple" => [":federated_timeline_removal", []]},
               %{"tuple" => [":reject", ["~r/comp[lL][aA][iI][nN]er/"]]},
               %{"tuple" => [":replace", []]}
             ]) == [
               federated_timeline_removal: [],
               reject: [~r/comp[lL][aA][iI][nN]er/],
               replace: []
             ]
    end

    test "complex keyword with tuples with more than 2 values" do
      assert Converter.to_elixir_types([
               %{
                 "tuple" => [
                   ":http",
                   [
                     %{
                       "tuple" => [
                         ":key1",
                         [
                           %{
                             "tuple" => [
                               ":_",
                               [
                                 %{
                                   "tuple" => [
                                     "/api/v1/streaming",
                                     "Pleroma.Web.MastodonAPI.WebsocketHandler",
                                     []
                                   ]
                                 },
                                 %{
                                   "tuple" => [
                                     "/websocket",
                                     "Phoenix.Endpoint.CowboyWebSocket",
                                     %{
                                       "tuple" => [
                                         "Phoenix.Transports.WebSocket",
                                         %{
                                           "tuple" => [
                                             "Pleroma.Web.Endpoint",
                                             "Pleroma.Web.UserSocket",
                                             []
                                           ]
                                         }
                                       ]
                                     }
                                   ]
                                 },
                                 %{
                                   "tuple" => [
                                     ":_",
                                     "Phoenix.Endpoint.Cowboy2Handler",
                                     %{"tuple" => ["Pleroma.Web.Endpoint", []]}
                                   ]
                                 }
                               ]
                             ]
                           }
                         ]
                       ]
                     }
                   ]
                 ]
               }
             ]) == [
               http: [
                 key1: [
                   {:_,
                    [
                      {"/api/v1/streaming", Pleroma.Web.MastodonAPI.WebsocketHandler, []},
                      {"/websocket", Phoenix.Endpoint.CowboyWebSocket,
                       {Phoenix.Transports.WebSocket,
                        {Pleroma.Web.Endpoint, Pleroma.Web.UserSocket, []}}},
                      {:_, Phoenix.Endpoint.Cowboy2Handler, {Pleroma.Web.Endpoint, []}}
                    ]}
                 ]
               ]
             ]
    end
  end

  describe "to_json_types" do
    test "list" do
      assert Converter.to_json_types(["0", 1, true, :atom, Pleroma.Upload]) == [
               "0",
               1,
               true,
               ":atom",
               "Pleroma.Upload"
             ]
    end

    test "regex" do
      assert Converter.to_json_types(~r/regex/i) == "~r/regex/i"
    end

    test "map" do
      assert Converter.to_json_types(%{"a" => "b", "c" => 1, "d" => true, "e" => :atom}) == %{
               "a" => "b",
               "c" => 1,
               "d" => true,
               "e" => ":atom"
             }
    end

    test ":args list" do
      assert Converter.to_json_types({:args, [{1, "a"}, "string"]}) == %{
               "tuple" => [":args", ["{1, \"a\"}", "string"]]
             }
    end

    test ":proxy_url tuple with localhost" do
      assert Converter.to_json_types({:proxy_url, {:socks, :localhost, 1234}}) == %{
               "tuple" => [":proxy_url", %{"tuple" => [":socks", "localhost", 1234]}]
             }
    end

    test ":proxy_url tuple" do
      assert Converter.to_json_types({:proxy_url, {:socks, {127, 0, 0, 1}, 1234}}) == %{
               "tuple" => [":proxy_url", %{"tuple" => [":socks", "127.0.0.1", 1234]}]
             }
    end

    test ":proxy_url tuple domain" do
      assert Converter.to_json_types({:proxy_url, {:socks5, "domain.com", 1234}}) == %{
               "tuple" => [":proxy_url", %{"tuple" => [":socks5", "domain.com", 1234]}]
             }
    end

    test "tuple" do
      assert Converter.to_json_types({1, "a"}) == %{"tuple" => [1, "a"]}
    end

    test "string" do
      assert Converter.to_json_types("string") == "string"
    end

    test "boolean" do
      assert Converter.to_json_types(true) == true
    end

    test "integer" do
      assert Converter.to_json_types(123) == 123
    end

    test "nil" do
      assert Converter.to_json_types(nil) == nil
    end

    test "ssl type" do
      assert Converter.to_json_types(:"tlsv1.1") == ":tlsv1.1"
    end

    test "atom" do
      assert Converter.to_json_types(:atom) == ":atom"
    end
  end

  describe "string_to_elixir_types/1" do
    test "atom" do
      assert Converter.string_to_elixir_types(":localhost") == :localhost
    end

    test "module" do
      assert Converter.string_to_elixir_types("Pleroma.Upload") == Pleroma.Upload
    end

    test "regex" do
      assert Converter.string_to_elixir_types("~r/regex/i") == ~r/regex/i
    end

    test "string" do
      assert Converter.string_to_elixir_types("string") == "string"
    end
  end
end
