# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.AdminAPI.ConfigControllerTest do
  use Pleroma.Web.ConnCase

  import Pleroma.Factory

  alias Pleroma.Config

  setup do
    admin = insert(:user, is_admin: true)
    token = insert(:oauth_admin_token, user: admin)

    conn =
      build_conn()
      |> assign(:user, admin)
      |> assign(:token, token)
      |> put_req_header("content-type", "application/json")

    on_exit(fn -> Pleroma.Application.ConfigDependentDeps.clear_state() end)
    {:ok, %{admin: admin, token: token, conn: conn}}
  end

  describe "GET /api/pleroma/admin/config" do
    setup do: clear_config(:configurable_from_database, true)

    test "when configuration from database is off", %{conn: conn} do
      clear_config(:configurable_from_database, false)

      assert conn
             |> get("/api/pleroma/admin/config")
             |> json_response_and_validate_schema(400) ==
               %{
                 "error" => "To use this endpoint you need to enable configuration from database."
               }
    end

    test "with settings only in db", %{conn: conn} do
      config1 = insert(:config)
      config2 = insert(:config)

      conn = get(conn, "/api/pleroma/admin/config?only_db=true")

      %{
        "configs" => [
          %{
            "group" => ":pleroma",
            "key" => key1,
            "value" => _
          },
          %{
            "group" => ":pleroma",
            "key" => key2,
            "value" => _
          }
        ]
      } = json_response_and_validate_schema(conn, 200)

      assert key1 == inspect(config1.key)
      assert key2 == inspect(config2.key)
    end

    test "db is added to settings that are in db", %{conn: conn} do
      _config = insert(:config, key: :instance, value: [name: "Some name"])

      %{"configs" => configs} =
        conn
        |> get("/api/pleroma/admin/config")
        |> json_response_and_validate_schema(200)

      [instance_config] =
        Enum.filter(configs, fn %{"group" => group, "key" => key} ->
          group == ":pleroma" and key == ":instance"
        end)

      assert instance_config["db"] == [":name"]
    end

    test "setting with value not keyword", %{conn: conn} do
      _config =
        insert(:config,
          key: Pleroma.Web.Auth.Authenticator,
          value: Pleroma.Web.Auth.LDAPAuthenticator
        )

      %{"configs" => configs} =
        conn
        |> get("/api/pleroma/admin/config")
        |> json_response_and_validate_schema(200)

      [instance_config] =
        Enum.filter(configs, fn %{"group" => group, "key" => key} ->
          group == ":pleroma" and key == "Pleroma.Web.Auth.Authenticator"
        end)

      assert instance_config["db"] == ["Pleroma.Web.Auth.Authenticator"]
      assert instance_config["value"] == "Pleroma.Web.Auth.LDAPAuthenticator"
    end

    test "merged default setting with db settings", %{conn: conn} do
      config1 = insert(:config)
      config2 = insert(:config)

      config3 =
        insert(:config,
          value: [k1: :v1, k2: :v2]
        )

      %{"configs" => configs} =
        conn
        |> get("/api/pleroma/admin/config")
        |> json_response_and_validate_schema(200)

      assert length(configs) > 3

      saved_configs = [config1, config2, config3]
      keys = Enum.map(saved_configs, &inspect(&1.key))
      values = Map.new(saved_configs, fn config -> {config.key, config.value} end)

      configs =
        Enum.filter(configs, fn %{"group" => group, "key" => key} ->
          group == ":pleroma" and key in keys
        end)
        |> Pleroma.Config.Converter.to_elixir_types()

      assert length(configs) == 3

      Enum.each(configs, fn %{"key" => key, "value" => value} ->
        assert values[key] == value
      end)
    end

    test "subkeys with full update right merge", %{conn: conn} do
      insert(:config,
        key: ":emoji",
        value: [groups: [a: 1, b: 2], key: [a: 1]]
      )

      insert(:config,
        key: ":assets",
        value: [mascots: [a: 1, b: 2], key: [a: 1]]
      )

      %{"configs" => configs} =
        conn
        |> get("/api/pleroma/admin/config")
        |> json_response_and_validate_schema(200)

      vals =
        Enum.filter(configs, fn %{"group" => group, "key" => key} ->
          group == ":pleroma" and key in [":emoji", ":assets"]
        end)

      emoji = Enum.find(vals, fn %{"key" => key} -> key == ":emoji" end)
      assets = Enum.find(vals, fn %{"key" => key} -> key == ":assets" end)

      emoji_val = Pleroma.Config.Converter.to_elixir_types(emoji["value"])
      assets_val = Pleroma.Config.Converter.to_elixir_types(assets["value"])

      assert emoji_val[:groups] == [a: 1, b: 2]
      assert assets_val[:mascots] == [a: 1, b: 2]
    end

    test "with valid `admin_token` query parameter, skips OAuth scopes check" do
      clear_config([:admin_token], "password123")

      build_conn()
      |> get("/api/pleroma/admin/config?admin_token=password123")
      |> json_response_and_validate_schema(200)
    end
  end

  test "POST /api/pleroma/admin/config with configdb disabled", %{conn: conn} do
    clear_config(:configurable_from_database, false)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/pleroma/admin/config", %{"configs" => []})

    assert json_response_and_validate_schema(conn, 400) ==
             %{"error" => "To use this endpoint you need to enable configuration from database."}
  end

  describe "POST /api/pleroma/admin/config" do
    setup do
      http = Application.get_env(:pleroma, :http)

      on_exit(fn ->
        Application.delete_env(:pleroma, :key1)
        Application.delete_env(:pleroma, :key2)
        Application.delete_env(:pleroma, :key3)
        Application.delete_env(:pleroma, :key4)
        Application.delete_env(:pleroma, :keyaa1)
        Application.delete_env(:pleroma, :keyaa2)
        Application.delete_env(:pleroma, Pleroma.Web.Endpoint.NotReal)
        Application.delete_env(:pleroma, Pleroma.Captcha.NotReal)
        Application.put_env(:pleroma, :http, http)
        Application.put_env(:tesla, :adapter, Tesla.Mock)
      end)
    end

    setup do: clear_config(:configurable_from_database, true)

    test "create new config setting in db", %{conn: conn} do
      ueberauth = Application.get_env(:ueberauth, Ueberauth)
      on_exit(fn -> Application.put_env(:ueberauth, Ueberauth, ueberauth) end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{group: ":pleroma", key: ":key1", value: [%{"tuple" => [":key", "value1"]}]},
            %{
              group: ":ueberauth",
              key: "Ueberauth",
              value: [%{"tuple" => [":consumer_secret", "aaaa"]}]
            },
            %{
              group: ":pleroma",
              key: ":key2",
              value: [
                %{"tuple" => [":nested_1", "nested_value1"]},
                %{
                  "tuple" => [
                    ":nested_2",
                    [
                      %{":nested_22" => "nested_value222"},
                      %{":nested_33" => %{":nested_44" => "nested_444"}}
                    ]
                  ]
                }
              ]
            },
            %{
              group: ":pleroma",
              key: ":key3",
              value: [
                %{"tuple" => [":key", ":nested_3"]},
                %{"tuple" => [":nested_33", "nested_33"]},
                %{"tuple" => [":key", true]}
              ]
            },
            %{
              group: ":pleroma",
              key: ":key4",
              value: [
                %{"tuple" => [":nested_5", ":upload"]},
                %{"tuple" => [":endpoint", "https://example.com"]}
              ]
            },
            %{
              group: ":idna",
              key: ":key5",
              value: [%{"tuple" => [":string", "Pleroma.Captcha.NotReal"]}]
            }
          ]
        })

      assert json_response_and_validate_schema(conn, 200) == %{
               "configs" => [
                 %{
                   "db" => [":consumer_secret"],
                   "group" => ":ueberauth",
                   "key" => "Ueberauth",
                   "value" => [%{"tuple" => [":consumer_secret", "aaaa"]}]
                 },
                 %{
                   "db" => [":nested_5", ":endpoint"],
                   "group" => ":pleroma",
                   "key" => ":key4",
                   "value" => [
                     %{"tuple" => [":nested_5", ":upload"]},
                     %{"tuple" => [":endpoint", "https://example.com"]}
                   ]
                 },
                 %{
                   "db" => [":key", ":nested_33", ":key"],
                   "group" => ":pleroma",
                   "key" => ":key3",
                   "value" => [
                     %{"tuple" => [":key", ":nested_3"]},
                     %{"tuple" => [":nested_33", "nested_33"]},
                     %{"tuple" => [":key", true]}
                   ]
                 },
                 %{
                   "db" => [":nested_1", ":nested_2"],
                   "group" => ":pleroma",
                   "key" => ":key2",
                   "value" => [
                     %{"tuple" => [":nested_1", "nested_value1"]},
                     %{
                       "tuple" => [
                         ":nested_2",
                         [
                           %{":nested_22" => "nested_value222"},
                           %{":nested_33" => %{":nested_44" => "nested_444"}}
                         ]
                       ]
                     }
                   ]
                 },
                 %{
                   "db" => [":key"],
                   "group" => ":pleroma",
                   "key" => ":key1",
                   "value" => [%{"tuple" => [":key", "value1"]}]
                 },
                 %{
                   "db" => [":string"],
                   "group" => ":idna",
                   "key" => ":key5",
                   "value" => [%{"tuple" => [":string", "Pleroma.Captcha.NotReal"]}]
                 }
               ],
               "need_reboot" => false
             }

      assert Application.get_env(:pleroma, :key1) == [key: "value1"]

      assert Application.get_env(:pleroma, :key2) == [
               nested_1: "nested_value1",
               nested_2: [
                 %{nested_22: "nested_value222"},
                 %{nested_33: %{nested_44: "nested_444"}}
               ]
             ]

      assert Application.get_env(:pleroma, :key3) == [
               key: :nested_3,
               nested_33: "nested_33",
               key: true
             ]

      assert Application.get_env(:pleroma, :key4) == [
               nested_5: :upload,
               endpoint: "https://example.com"
             ]

      assert Application.get_env(:idna, :key5) == [string: Pleroma.Captcha.NotReal]
    end

    test "save configs setting without key", %{conn: conn} do
      quack_env = Application.get_all_env(:quack)

      on_exit(fn ->
        Application.put_all_env(quack: quack_env)
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              group: ":quack",
              value: [
                %{"tuple" => [":level", ":info"]},
                %{"tuple" => [":meta", [":none"]]},
                %{"tuple" => [":webhook_url", "https://hooks.slack.com/services/KEY"]}
              ]
            }
          ]
        })

      assert json_response_and_validate_schema(conn, 200) == %{
               "configs" => [
                 %{
                   "group" => ":quack",
                   "key" => nil,
                   "value" => [
                     %{"tuple" => [":level", ":info"]},
                     %{"tuple" => [":meta", [":none"]]},
                     %{"tuple" => [":webhook_url", "https://hooks.slack.com/services/KEY"]}
                   ],
                   "db" => [":level", ":meta", ":webhook_url"]
                 }
               ],
               "need_reboot" => false
             }

      assert Application.get_env(:quack, :level) == :info
      assert Application.get_env(:quack, :meta) == [:none]
      assert Application.get_env(:quack, :webhook_url) == "https://hooks.slack.com/services/KEY"
    end

    test "saving config with partial update", %{conn: conn} do
      insert(:config, key: ":key1", value: [key1: 1, key2: 2])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{group: ":pleroma", key: ":key1", value: [%{"tuple" => [":key3", 3]}]}
          ]
        })

      assert json_response_and_validate_schema(conn, 200) == %{
               "configs" => [
                 %{
                   "group" => ":pleroma",
                   "key" => ":key1",
                   "value" => [
                     %{"tuple" => [":key1", 1]},
                     %{"tuple" => [":key2", 2]},
                     %{"tuple" => [":key3", 3]}
                   ],
                   "db" => [":key1", ":key2", ":key3"]
                 }
               ],
               "need_reboot" => false
             }
    end

    test "saving config which need pleroma reboot", %{conn: conn} do
      clear_config(:chat)

      assert conn
             |> put_req_header("content-type", "application/json")
             |> post(
               "/api/pleroma/admin/config",
               %{
                 configs: [
                   %{group: ":pleroma", key: ":chat", value: [%{"tuple" => [":enabled", true]}]}
                 ]
               }
             )
             |> json_response_and_validate_schema(200) == %{
               "configs" => [
                 %{
                   "db" => [":enabled"],
                   "group" => ":pleroma",
                   "key" => ":chat",
                   "value" => [%{"tuple" => [":enabled", true]}]
                 }
               ],
               "need_reboot" => true
             }

      configs =
        conn
        |> get("/api/pleroma/admin/config")
        |> json_response_and_validate_schema(200)

      assert configs["need_reboot"]

      assert conn |> get("/api/pleroma/admin/restart") |> json_response(200) ==
               %{}

      configs =
        conn
        |> get("/api/pleroma/admin/config")
        |> json_response_and_validate_schema(200)

      assert configs["need_reboot"] == false
    end

    test "update setting which need reboot, don't change reboot flag until reboot", %{conn: conn} do
      clear_config(:chat)

      assert conn
             |> put_req_header("content-type", "application/json")
             |> post(
               "/api/pleroma/admin/config",
               %{
                 configs: [
                   %{group: ":pleroma", key: ":chat", value: [%{"tuple" => [":enabled", true]}]}
                 ]
               }
             )
             |> json_response_and_validate_schema(200) == %{
               "configs" => [
                 %{
                   "db" => [":enabled"],
                   "group" => ":pleroma",
                   "key" => ":chat",
                   "value" => [%{"tuple" => [":enabled", true]}]
                 }
               ],
               "need_reboot" => true
             }

      assert conn
             |> put_req_header("content-type", "application/json")
             |> post("/api/pleroma/admin/config", %{
               configs: [
                 %{group: ":pleroma", key: ":key1", value: [%{"tuple" => [":key3", 3]}]}
               ]
             })
             |> json_response_and_validate_schema(200) == %{
               "configs" => [
                 %{
                   "group" => ":pleroma",
                   "key" => ":key1",
                   "value" => [
                     %{"tuple" => [":key3", 3]}
                   ],
                   "db" => [":key3"]
                 }
               ],
               "need_reboot" => true
             }

      assert conn |> get("/api/pleroma/admin/restart") |> json_response(200) ==
               %{}

      configs =
        conn
        |> get("/api/pleroma/admin/config")
        |> json_response_and_validate_schema(200)

      assert configs["need_reboot"] == false
    end

    test "saving config with nested merge", %{conn: conn} do
      insert(:config, key: :key1, value: [key1: 1, key2: [k1: 1, k2: 2]])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              group: ":pleroma",
              key: ":key1",
              value: [
                %{"tuple" => [":key3", 3]},
                %{
                  "tuple" => [
                    ":key2",
                    [
                      %{"tuple" => [":k2", 1]},
                      %{"tuple" => [":k3", 3]}
                    ]
                  ]
                }
              ]
            }
          ]
        })

      assert json_response_and_validate_schema(conn, 200) == %{
               "configs" => [
                 %{
                   "group" => ":pleroma",
                   "key" => ":key1",
                   "value" => [
                     %{"tuple" => [":key1", 1]},
                     %{"tuple" => [":key3", 3]},
                     %{
                       "tuple" => [
                         ":key2",
                         [
                           %{"tuple" => [":k1", 1]},
                           %{"tuple" => [":k2", 1]},
                           %{"tuple" => [":k3", 3]}
                         ]
                       ]
                     }
                   ],
                   "db" => [":key1", ":key3", ":key2"]
                 }
               ],
               "need_reboot" => false
             }
    end

    test "saving special atoms", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          "configs" => [
            %{
              "group" => ":pleroma",
              "key" => ":key1",
              "value" => [
                %{
                  "tuple" => [
                    ":ssl_options",
                    [%{"tuple" => [":versions", [":tlsv1", ":tlsv1.1", ":tlsv1.2"]]}]
                  ]
                }
              ]
            }
          ]
        })

      assert json_response_and_validate_schema(conn, 200) == %{
               "configs" => [
                 %{
                   "group" => ":pleroma",
                   "key" => ":key1",
                   "value" => [
                     %{
                       "tuple" => [
                         ":ssl_options",
                         [%{"tuple" => [":versions", [":tlsv1", ":tlsv1.1", ":tlsv1.2"]]}]
                       ]
                     }
                   ],
                   "db" => [":ssl_options"]
                 }
               ],
               "need_reboot" => false
             }

      assert Application.get_env(:pleroma, :key1) == [
               ssl_options: [versions: [:tlsv1, :"tlsv1.1", :"tlsv1.2"]]
             ]
    end

    test "update config setting & delete with fallback to default value", %{conn: conn} do
      ueberauth = Application.get_env(:ueberauth, Ueberauth)
      insert(:config, key: :keyaa1, value: [key: "value"])
      insert(:config, key: :keyaa2, value: [key: "value"])

      resp =
        post(conn, "/api/pleroma/admin/config", %{
          configs: [
            %{
              group: ":pleroma",
              key: ":keyaa1",
              value: [
                %{"tuple" => [":key", "value2"]},
                %{"tuple" => [":key2", "value"]}
              ]
            },
            %{group: ":pleroma", key: ":keyaa2", value: [%{"tuple" => [":key", "value2"]}]},
            %{
              group: ":ueberauth",
              key: "Ueberauth",
              value: [
                %{"tuple" => [":another_key", "somevalue"]},
                %{"tuple" => [":another", "somevalue"]}
              ]
            },
            %{
              group: ":pleroma",
              key: "Pleroma.Uploaders.Local",
              delete: true
            }
          ]
        })

      assert json_response_and_validate_schema(resp, 200) == %{
               "configs" => [
                 %{
                   "db" => [":another_key", ":another"],
                   "group" => ":ueberauth",
                   "key" => "Ueberauth",
                   "value" => [
                     %{"tuple" => [":another_key", "somevalue"]},
                     %{"tuple" => [":another", "somevalue"]}
                   ]
                 },
                 %{
                   "group" => ":pleroma",
                   "key" => ":keyaa2",
                   "value" => [
                     %{"tuple" => [":key", "value2"]}
                   ],
                   "db" => [":key"]
                 },
                 %{
                   "group" => ":pleroma",
                   "key" => ":keyaa1",
                   "value" => [
                     %{"tuple" => [":key", "value2"]},
                     %{"tuple" => [":key2", "value"]}
                   ],
                   "db" => [":key", ":key2"]
                 }
               ],
               "need_reboot" => false
             }

      assert Application.get_env(:pleroma, :keyaa1) == [key: "value2", key2: "value"]
      assert Application.get_env(:pleroma, :keyaa2) == [key: "value2"]

      assert Application.get_env(:ueberauth, Ueberauth) == [
               base_path: "/oauth",
               providers: [],
               another_key: "somevalue",
               another: "somevalue"
             ]

      resp =
        post(conn, "/api/pleroma/admin/config", %{
          configs: [
            %{group: ":pleroma", key: ":keyaa2", delete: true},
            %{group: ":pleroma", key: ":keyaa1", delete: true, subkeys: [":key"]},
            %{
              group: ":ueberauth",
              key: "Ueberauth",
              delete: true
            }
          ]
        })

      assert json_response_and_validate_schema(resp, 200) == %{
               "configs" => [
                 %{
                   "db" => [":key2"],
                   "group" => ":pleroma",
                   "key" => ":keyaa1",
                   "value" => [%{"tuple" => [":key2", "value"]}]
                 }
               ],
               "need_reboot" => false
             }

      assert Application.get_env(:ueberauth, Ueberauth) == ueberauth
      refute Keyword.has_key?(Application.get_all_env(:pleroma), :keyaa2)
    end

    test "common config example", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              "group" => ":pleroma",
              "key" => "Pleroma.Captcha.NotReal",
              "value" => [
                %{"tuple" => [":enabled", false]},
                %{"tuple" => [":method", "Pleroma.Captcha.Kocaptcha"]},
                %{"tuple" => [":seconds_valid", 60]},
                %{"tuple" => [":path", ""]},
                %{"tuple" => [":key1", nil]},
                %{"tuple" => [":partial_chain", "&:hackney_connect.partial_chain/1"]},
                %{"tuple" => [":regex1", "~r/https:\/\/example.com/"]},
                %{"tuple" => [":regex2", "~r/https:\/\/example.com/u"]},
                %{"tuple" => [":regex3", "~r/https:\/\/example.com/i"]},
                %{"tuple" => [":regex4", "~r/https:\/\/example.com/s"]},
                %{"tuple" => [":name", "Pleroma"]}
              ]
            }
          ]
        })

      assert Config.get([Pleroma.Captcha.NotReal, :name]) == "Pleroma"

      assert json_response_and_validate_schema(conn, 200) == %{
               "configs" => [
                 %{
                   "group" => ":pleroma",
                   "key" => "Pleroma.Captcha.NotReal",
                   "value" => [
                     %{"tuple" => [":enabled", false]},
                     %{"tuple" => [":method", "Pleroma.Captcha.Kocaptcha"]},
                     %{"tuple" => [":seconds_valid", 60]},
                     %{"tuple" => [":path", ""]},
                     %{"tuple" => [":key1", nil]},
                     %{"tuple" => [":partial_chain", "&:hackney_connect.partial_chain/1"]},
                     %{"tuple" => [":regex1", "~r/https:\\/\\/example.com/"]},
                     %{"tuple" => [":regex2", "~r/https:\\/\\/example.com/u"]},
                     %{"tuple" => [":regex3", "~r/https:\\/\\/example.com/i"]},
                     %{"tuple" => [":regex4", "~r/https:\\/\\/example.com/s"]},
                     %{"tuple" => [":name", "Pleroma"]}
                   ],
                   "db" => [
                     ":enabled",
                     ":method",
                     ":seconds_valid",
                     ":path",
                     ":key1",
                     ":partial_chain",
                     ":regex1",
                     ":regex2",
                     ":regex3",
                     ":regex4",
                     ":name"
                   ]
                 }
               ],
               "need_reboot" => false
             }
    end

    test "tuples with more than two values", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              "group" => ":pleroma",
              "key" => "Pleroma.Web.Endpoint.NotReal",
              "value" => [
                %{
                  "tuple" => [
                    ":http",
                    [
                      %{
                        "tuple" => [
                          ":key2",
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
              ]
            }
          ]
        })

      assert json_response_and_validate_schema(conn, 200) == %{
               "configs" => [
                 %{
                   "group" => ":pleroma",
                   "key" => "Pleroma.Web.Endpoint.NotReal",
                   "value" => [
                     %{
                       "tuple" => [
                         ":http",
                         [
                           %{
                             "tuple" => [
                               ":key2",
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
                   ],
                   "db" => [":http"]
                 }
               ],
               "need_reboot" => false
             }
    end

    test "settings with nesting map", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              "group" => ":pleroma",
              "key" => ":key1",
              "value" => [
                %{"tuple" => [":key2", "some_val"]},
                %{
                  "tuple" => [
                    ":key3",
                    %{
                      ":max_options" => 20,
                      ":max_option_chars" => 200,
                      ":min_expiration" => 0,
                      ":max_expiration" => 31_536_000,
                      "nested" => %{
                        ":max_options" => 20,
                        ":max_option_chars" => 200,
                        ":min_expiration" => 0,
                        ":max_expiration" => 31_536_000
                      }
                    }
                  ]
                }
              ]
            }
          ]
        })

      assert json_response_and_validate_schema(conn, 200) ==
               %{
                 "configs" => [
                   %{
                     "group" => ":pleroma",
                     "key" => ":key1",
                     "value" => [
                       %{"tuple" => [":key2", "some_val"]},
                       %{
                         "tuple" => [
                           ":key3",
                           %{
                             ":max_expiration" => 31_536_000,
                             ":max_option_chars" => 200,
                             ":max_options" => 20,
                             ":min_expiration" => 0,
                             "nested" => %{
                               ":max_expiration" => 31_536_000,
                               ":max_option_chars" => 200,
                               ":max_options" => 20,
                               ":min_expiration" => 0
                             }
                           }
                         ]
                       }
                     ],
                     "db" => [":key2", ":key3"]
                   }
                 ],
                 "need_reboot" => false
               }
    end

    test "queues key as atom", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              "group" => ":oban",
              "key" => ":queues",
              "value" => [
                %{"tuple" => [":federator_incoming", 50]},
                %{"tuple" => [":federator_outgoing", 50]},
                %{"tuple" => [":web_push", 50]},
                %{"tuple" => [":mailer", 10]},
                %{"tuple" => [":transmogrifier", 20]},
                %{"tuple" => [":scheduled_activities", 10]},
                %{"tuple" => [":background", 5]}
              ]
            }
          ]
        })

      assert json_response_and_validate_schema(conn, 200) == %{
               "configs" => [
                 %{
                   "group" => ":oban",
                   "key" => ":queues",
                   "value" => [
                     %{"tuple" => [":federator_incoming", 50]},
                     %{"tuple" => [":federator_outgoing", 50]},
                     %{"tuple" => [":web_push", 50]},
                     %{"tuple" => [":mailer", 10]},
                     %{"tuple" => [":transmogrifier", 20]},
                     %{"tuple" => [":scheduled_activities", 10]},
                     %{"tuple" => [":background", 5]}
                   ],
                   "db" => [
                     ":federator_incoming",
                     ":federator_outgoing",
                     ":web_push",
                     ":mailer",
                     ":transmogrifier",
                     ":scheduled_activities",
                     ":background"
                   ]
                 }
               ],
               "need_reboot" => false
             }
    end

    test "delete part of settings by atom subkeys", %{conn: conn} do
      insert(:config,
        key: :keyaa1,
        value: [subkey1: "val1", subkey2: "val2", subkey3: "val3"]
      )

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              group: ":pleroma",
              key: ":keyaa1",
              subkeys: [":subkey1", ":subkey3"],
              delete: true
            }
          ]
        })

      assert json_response_and_validate_schema(conn, 200) == %{
               "configs" => [
                 %{
                   "group" => ":pleroma",
                   "key" => ":keyaa1",
                   "value" => [%{"tuple" => [":subkey2", "val2"]}],
                   "db" => [":subkey2"]
                 }
               ],
               "need_reboot" => false
             }
    end

    test "proxy tuple localhost", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              group: ":pleroma",
              key: ":http",
              value: [
                %{"tuple" => [":proxy_url", %{"tuple" => [":socks5", "localhost", 1234]}]}
              ]
            }
          ]
        })

      assert %{
               "configs" => [
                 %{
                   "group" => ":pleroma",
                   "key" => ":http",
                   "value" => value,
                   "db" => db
                 }
               ]
             } = json_response_and_validate_schema(conn, 200)

      assert %{"tuple" => [":proxy_url", %{"tuple" => [":socks5", "localhost", 1234]}]} in value
      assert ":proxy_url" in db
    end

    test "proxy tuple domain", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              group: ":pleroma",
              key: ":http",
              value: [
                %{"tuple" => [":proxy_url", %{"tuple" => [":socks5", "domain.com", 1234]}]}
              ]
            }
          ]
        })

      assert %{
               "configs" => [
                 %{
                   "group" => ":pleroma",
                   "key" => ":http",
                   "value" => value,
                   "db" => db
                 }
               ]
             } = json_response_and_validate_schema(conn, 200)

      assert %{"tuple" => [":proxy_url", %{"tuple" => [":socks5", "domain.com", 1234]}]} in value
      assert ":proxy_url" in db
    end

    test "proxy tuple ip", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              group: ":pleroma",
              key: ":http",
              value: [
                %{"tuple" => [":proxy_url", %{"tuple" => [":socks5", "127.0.0.1", 1234]}]}
              ]
            }
          ]
        })

      assert %{
               "configs" => [
                 %{
                   "group" => ":pleroma",
                   "key" => ":http",
                   "value" => value,
                   "db" => db
                 }
               ]
             } = json_response_and_validate_schema(conn, 200)

      assert %{"tuple" => [":proxy_url", %{"tuple" => [":socks5", "127.0.0.1", 1234]}]} in value
      assert ":proxy_url" in db
    end

    test "doesn't set keys not in the whitelist", %{conn: conn} do
      clear_config(:database_config_whitelist, [
        {:pleroma, :key1},
        {:pleroma, :key2},
        {:pleroma, Pleroma.Captcha.NotReal},
        {:not_real}
      ])

      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/pleroma/admin/config", %{
        configs: [
          %{group: ":pleroma", key: ":key1", value: [%{"tuple" => [":key", "value1"]}]},
          %{group: ":pleroma", key: ":key2", value: [%{"tuple" => [":key", "value2"]}]},
          %{group: ":pleroma", key: ":key3", value: [%{"tuple" => [":key", "value3"]}]},
          %{
            group: ":pleroma",
            key: "Pleroma.Web.Endpoint.NotReal",
            value: [%{"tuple" => [":key", "value4"]}]
          },
          %{
            group: ":pleroma",
            key: "Pleroma.Captcha.NotReal",
            value: [%{"tuple" => [":key", "value5"]}]
          },
          %{group: ":not_real", key: ":anything", value: [%{"tuple" => [":key", "value6"]}]}
        ]
      })

      assert Application.get_env(:pleroma, :key1) == [key: "value1"]
      assert Application.get_env(:pleroma, :key2) == [key: "value2"]
      assert Application.get_env(:pleroma, :key3) == nil
      assert Application.get_env(:pleroma, Pleroma.Web.Endpoint.NotReal) == nil
      assert Application.get_env(:pleroma, Pleroma.Captcha.NotReal) == [key: "value5"]
      assert Application.get_env(:not_real, :anything) == [key: "value6"]
    end

    test "args for Pleroma.Upload.Filter.Mogrify with custom tuples", %{conn: conn} do
      clear_config(Pleroma.Upload.Filter.Mogrify)

      assert conn
             |> put_req_header("content-type", "application/json")
             |> post("/api/pleroma/admin/config", %{
               configs: [
                 %{
                   group: ":pleroma",
                   key: "Pleroma.Upload.Filter.Mogrify",
                   value: [
                     %{"tuple" => [":args", ["auto-orient", "strip"]]}
                   ]
                 }
               ]
             })
             |> json_response_and_validate_schema(200) == %{
               "configs" => [
                 %{
                   "group" => ":pleroma",
                   "key" => "Pleroma.Upload.Filter.Mogrify",
                   "value" => [
                     %{"tuple" => [":args", ["auto-orient", "strip"]]}
                   ],
                   "db" => [":args"]
                 }
               ],
               "need_reboot" => false
             }

      assert Config.get(Pleroma.Upload.Filter.Mogrify) == [args: ["auto-orient", "strip"]]

      assert conn
             |> put_req_header("content-type", "application/json")
             |> post("/api/pleroma/admin/config", %{
               configs: [
                 %{
                   group: ":pleroma",
                   key: "Pleroma.Upload.Filter.Mogrify",
                   value: [
                     %{
                       "tuple" => [
                         ":args",
                         [
                           "auto-orient",
                           "strip",
                           "{\"implode\", \"1\"}",
                           "{\"resize\", \"3840x1080>\"}"
                         ]
                       ]
                     }
                   ]
                 }
               ]
             })
             |> json_response(200) == %{
               "configs" => [
                 %{
                   "group" => ":pleroma",
                   "key" => "Pleroma.Upload.Filter.Mogrify",
                   "value" => [
                     %{
                       "tuple" => [
                         ":args",
                         [
                           "auto-orient",
                           "strip",
                           "{\"implode\", \"1\"}",
                           "{\"resize\", \"3840x1080>\"}"
                         ]
                       ]
                     }
                   ],
                   "db" => [":args"]
                 }
               ],
               "need_reboot" => false
             }

      assert Config.get(Pleroma.Upload.Filter.Mogrify) == [
               args: ["auto-orient", "strip", {"implode", "1"}, {"resize", "3840x1080>"}]
             ]
    end

    test "enables the welcome messages", %{conn: conn} do
      clear_config([:welcome])

      params = %{
        "group" => ":pleroma",
        "key" => ":welcome",
        "value" => [
          %{
            "tuple" => [
              ":direct_message",
              [
                %{"tuple" => [":enabled", true]},
                %{"tuple" => [":message", "Welcome to Pleroma!"]},
                %{"tuple" => [":sender_nickname", "pleroma"]}
              ]
            ]
          },
          %{
            "tuple" => [
              ":chat_message",
              [
                %{"tuple" => [":enabled", true]},
                %{"tuple" => [":message", "Welcome to Pleroma!"]},
                %{"tuple" => [":sender_nickname", "pleroma"]}
              ]
            ]
          },
          %{
            "tuple" => [
              ":email",
              [
                %{"tuple" => [":enabled", true]},
                %{"tuple" => [":sender", %{"tuple" => ["pleroma@dev.dev", "Pleroma"]}]},
                %{"tuple" => [":subject", "Welcome to <%= instance_name %>!"]},
                %{"tuple" => [":html", "Welcome to <%= instance_name %>!"]},
                %{"tuple" => [":text", "Welcome to <%= instance_name %>!"]}
              ]
            ]
          }
        ]
      }

      refute Pleroma.User.WelcomeEmail.enabled?()
      refute Pleroma.User.WelcomeMessage.enabled?()
      refute Pleroma.User.WelcomeChatMessage.enabled?()

      res =
        assert conn
               |> put_req_header("content-type", "application/json")
               |> post("/api/pleroma/admin/config", %{"configs" => [params]})
               |> json_response_and_validate_schema(200)

      assert Pleroma.User.WelcomeEmail.enabled?()
      assert Pleroma.User.WelcomeMessage.enabled?()
      assert Pleroma.User.WelcomeChatMessage.enabled?()

      assert res == %{
               "configs" => [
                 %{
                   "db" => [":direct_message", ":chat_message", ":email"],
                   "group" => ":pleroma",
                   "key" => ":welcome",
                   "value" => params["value"]
                 }
               ],
               "need_reboot" => false
             }
    end

    test "value bad format error", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              group: ":quack",
              value: %{}
            }
          ]
        })

      assert json_response_and_validate_schema(conn, 400) == %{
               "error" =>
                 "Updating config failed: :value_must_be_keyword, group: quack, key: , value: %{}"
             }
    end

    test "error when value is list", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              group: ":quack",
              value: [1]
            }
          ]
        })

      assert json_response_and_validate_schema(conn, 400) == %{
               "error" =>
                 "Updating config failed: :value_must_be_keyword, group: quack, key: , value: [1]"
             }
    end

    test "saving pleroma group with value not a keyword", %{conn: conn} do
      clear_config(Pleroma.Web.Auth.Authenticator)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/pleroma/admin/config", %{
          configs: [
            %{
              group: ":pleroma",
              key: "Pleroma.Web.Auth.Authenticator",
              value: "Pleroma.Web.Auth.LDAPAuthenticator"
            }
          ]
        })

      assert json_response_and_validate_schema(conn, 200) == %{
               "configs" => [
                 %{
                   "db" => ["Pleroma.Web.Auth.Authenticator"],
                   "group" => ":pleroma",
                   "key" => "Pleroma.Web.Auth.Authenticator",
                   "value" => "Pleroma.Web.Auth.LDAPAuthenticator"
                 }
               ],
               "need_reboot" => false
             }

      assert Application.get_env(:pleroma, Pleroma.Web.Auth.Authenticator) ==
               Pleroma.Web.Auth.LDAPAuthenticator
    end
  end

  describe "GET /api/pleroma/admin/config/descriptions" do
    test "structure", %{conn: conn} do
      conn = get(conn, "/api/pleroma/admin/config/descriptions")

      assert [child | _others] = json_response_and_validate_schema(conn, 200)

      assert child["children"]
      assert child["key"]
      assert String.starts_with?(child["group"], ":")
      assert child["description"]
    end

    test "filters by database configuration whitelist", %{conn: conn} do
      clear_config(:database_config_whitelist, [
        {:pleroma, :instance},
        {:pleroma, :activitypub},
        {:pleroma, Pleroma.Upload},
        {:esshd}
      ])

      conn = get(conn, "/api/pleroma/admin/config/descriptions")

      children = json_response_and_validate_schema(conn, 200)

      assert length(children) == 4

      assert Enum.count(children, fn c -> c["group"] == ":pleroma" end) == 3

      instance = Enum.find(children, fn c -> c["key"] == ":instance" end)
      assert instance["children"]

      activitypub = Enum.find(children, fn c -> c["key"] == ":activitypub" end)
      assert activitypub["children"]

      web_endpoint = Enum.find(children, fn c -> c["key"] == "Pleroma.Upload" end)
      assert web_endpoint["children"]

      esshd = Enum.find(children, fn c -> c["group"] == ":esshd" end)
      assert esshd["children"]
    end
  end

  describe "GET /api/pleroma/admin/config/versions/rollback" do
    setup do: clear_config(:configurable_from_database, true)

    test "success rollback", %{conn: conn} do
      version = insert(:config_version)
      insert(:config_version)
      insert(:config_version, current: true)

      conn
      |> get("/api/pleroma/admin/config/versions/rollback/#{version.id}")
      |> json_response_and_validate_schema(204)

      [config] = Pleroma.Repo.all(Pleroma.ConfigDB)
      assert config.value == version.backup[config.group][config.key]
    end

    test "not found error", %{conn: conn} do
      assert conn
             |> get("/api/pleroma/admin/config/versions/rollback/1")
             |> json_response_and_validate_schema(404) == %{
               "error" => "Not found"
             }
    end

    test "on rollback to version, which is current", %{conn: conn} do
      version = insert(:config_version, current: true)

      assert conn
             |> get("/api/pleroma/admin/config/versions/rollback/#{version.id}")
             |> json_response_and_validate_schema(400) == %{
               "error" => "Rollback is not possible: :version_is_already_current"
             }
    end

    test "when configuration from database is off", %{conn: conn} do
      clear_config(:configurable_from_database, false)

      assert conn
             |> get("/api/pleroma/admin/config/versions/rollback/1")
             |> json_response_and_validate_schema(400) ==
               %{
                 "error" => "To use this endpoint you need to enable configuration from database."
               }
    end
  end

  describe "GET /api/pleroma/admin/config/versions" do
    setup do: clear_config(:configurable_from_database, true)

    test "with no versions", %{conn: conn} do
      assert conn
             |> get("/api/pleroma/admin/config/versions")
             |> json_response_and_validate_schema(200) == %{"versions" => []}
    end

    test "with versions", %{conn: conn} do
      version = insert(:config_version, current: true)

      assert conn
             |> get("/api/pleroma/admin/config/versions")
             |> json_response_and_validate_schema(200) == %{
               "versions" => [
                 %{
                   "current" => true,
                   "id" => version.id,
                   "inserted_at" => Pleroma.Web.CommonAPI.Utils.to_masto_date(version.inserted_at)
                 }
               ]
             }
    end

    test "when configuration from database is off", %{conn: conn} do
      clear_config(:configurable_from_database, false)

      assert conn
             |> get("/api/pleroma/admin/config/versions")
             |> json_response_and_validate_schema(400) ==
               %{
                 "error" => "To use this endpoint you need to enable configuration from database."
               }
    end
  end
end

# Needed for testing
defmodule Pleroma.Web.Endpoint.NotReal do
end

defmodule Pleroma.Captcha.NotReal do
end
