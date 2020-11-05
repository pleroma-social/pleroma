# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.RegistrationUserTest do
  use Pleroma.Web.ConnCase

  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.UserInviteToken
  alias Pleroma.Web.OAuth.Token

  import Pleroma.Factory

  describe "create account by app" do
    setup do
      valid_params = %{
        username: "lain",
        email: "lain@example.org",
        password: "PlzDontHackLain",
        agreement: true
      }

      [valid_params: valid_params]
    end

    test "registers and logs in without :account_activation_required / :account_approval_required",
         %{conn: conn} do
      clear_config([:instance, :account_activation_required], false)
      clear_config([:instance, :account_approval_required], false)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/apps", %{
          client_name: "client_name",
          redirect_uris: "urn:ietf:wg:oauth:2.0:oob",
          scopes: "read, write, follow"
        })

      assert %{
               "client_id" => client_id,
               "client_secret" => client_secret,
               "id" => _,
               "name" => "client_name",
               "redirect_uri" => "urn:ietf:wg:oauth:2.0:oob",
               "vapid_key" => _,
               "website" => nil
             } = json_response_and_validate_schema(conn, 200)

      conn =
        post(conn, "/oauth/token", %{
          grant_type: "client_credentials",
          client_id: client_id,
          client_secret: client_secret
        })

      assert %{"access_token" => token, "refresh_token" => refresh, "scope" => scope} =
               json_response(conn, 200)

      assert token
      token_from_db = Repo.get_by(Token, token: token)
      assert token_from_db
      assert refresh
      assert scope == "read write follow"

      clear_config([User, :email_blacklist], ["example.org"])

      params = %{
        username: "lain",
        email: "lain@example.org",
        password: "PlzDontHackLain",
        bio: "Test Bio",
        agreement: true
      }

      response =
        build_conn()
        |> put_req_header("content-type", "multipart/form-data")
        |> put_req_header("authorization", "Bearer " <> token)
        |> post("/api/v1/accounts", params)
        |> json_response_and_validate_schema(400)

      assert response == %{
               "error" => "Please review the submission",
               "fields" => %{"email" => ["Email Invalid email"]},
               "identifier" => "review_submission"
             }

      Pleroma.Config.put([User, :email_blacklist], [])

      conn =
        build_conn()
        |> put_req_header("content-type", "multipart/form-data")
        |> put_req_header("authorization", "Bearer " <> token)
        |> post("/api/v1/accounts", params)

      %{
        "access_token" => token,
        "created_at" => _created_at,
        "scope" => ^scope,
        "token_type" => "Bearer"
      } = json_response_and_validate_schema(conn, 200)

      token_from_db = Repo.get_by(Token, token: token)
      assert token_from_db
      user = Repo.preload(token_from_db, :user).user

      assert user
      refute user.confirmation_pending
      refute user.approval_pending
    end

    test "registers but does not log in with :account_activation_required", %{conn: conn} do
      clear_config([:instance, :account_activation_required], true)
      clear_config([:instance, :account_approval_required], false)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/apps", %{
          client_name: "client_name",
          redirect_uris: "urn:ietf:wg:oauth:2.0:oob",
          scopes: "read, write, follow"
        })

      assert %{
               "client_id" => client_id,
               "client_secret" => client_secret,
               "id" => _,
               "name" => "client_name",
               "redirect_uri" => "urn:ietf:wg:oauth:2.0:oob",
               "vapid_key" => _,
               "website" => nil
             } = json_response_and_validate_schema(conn, 200)

      conn =
        post(conn, "/oauth/token", %{
          grant_type: "client_credentials",
          client_id: client_id,
          client_secret: client_secret
        })

      assert %{"access_token" => token, "refresh_token" => refresh, "scope" => scope} =
               json_response(conn, 200)

      assert token
      token_from_db = Repo.get_by(Token, token: token)
      assert token_from_db
      assert refresh
      assert scope == "read write follow"

      conn =
        build_conn()
        |> put_req_header("content-type", "multipart/form-data")
        |> put_req_header("authorization", "Bearer " <> token)
        |> post("/api/v1/accounts", %{
          username: "lain",
          email: "lain@example.org",
          password: "PlzDontHackLain",
          bio: "Test Bio",
          agreement: true
        })

      response = json_response_and_validate_schema(conn, 200)
      assert %{"identifier" => "missing_confirmed_email"} = response
      refute response["access_token"]
      refute response["token_type"]

      user = Repo.get_by(User, email: "lain@example.org")
      assert user.confirmation_pending
    end

    test "registers but does not log in with :account_approval_required", %{conn: conn} do
      clear_config([:instance, :account_approval_required], true)
      clear_config([:instance, :account_activation_required], false)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/apps", %{
          client_name: "client_name",
          redirect_uris: "urn:ietf:wg:oauth:2.0:oob",
          scopes: "read, write, follow"
        })

      assert %{
               "client_id" => client_id,
               "client_secret" => client_secret,
               "id" => _,
               "name" => "client_name",
               "redirect_uri" => "urn:ietf:wg:oauth:2.0:oob",
               "vapid_key" => _,
               "website" => nil
             } = json_response_and_validate_schema(conn, 200)

      conn =
        post(conn, "/oauth/token", %{
          grant_type: "client_credentials",
          client_id: client_id,
          client_secret: client_secret
        })

      assert %{"access_token" => token, "refresh_token" => refresh, "scope" => scope} =
               json_response(conn, 200)

      assert token
      token_from_db = Repo.get_by(Token, token: token)
      assert token_from_db
      assert refresh
      assert scope == "read write follow"

      conn =
        build_conn()
        |> put_req_header("content-type", "multipart/form-data")
        |> put_req_header("authorization", "Bearer " <> token)
        |> post("/api/v1/accounts", %{
          username: "lain",
          email: "lain@example.org",
          password: "PlzDontHackLain",
          bio: "Test Bio",
          agreement: true,
          reason: "I'm a cool dude, bro"
        })

      response = json_response_and_validate_schema(conn, 200)
      assert %{"identifier" => "awaiting_approval"} = response
      refute response["access_token"]
      refute response["token_type"]

      user = Repo.get_by(User, email: "lain@example.org")

      assert user.approval_pending
      assert user.registration_reason == "I'm a cool dude, bro"
    end

    test "returns error when user already registred", %{conn: conn, valid_params: valid_params} do
      _user = insert(:user, email: "lain@example.org")
      app_token = insert(:oauth_token, user: nil)

      res =
        conn
        |> put_req_header("authorization", "Bearer " <> app_token.token)
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/accounts", valid_params)
        |> json_response_and_validate_schema(400)

      assert res == %{
               "error" => "Please review the submission",
               "fields" => %{"email" => ["Email has already been taken"]},
               "identifier" => "review_submission"
             }
    end

    test "returns bad_request if missing required params", %{
      conn: conn,
      valid_params: valid_params
    } do
      app_token = insert(:oauth_token, user: nil)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> app_token.token)
        |> put_req_header("content-type", "application/json")

      res = post(conn, "/api/v1/accounts", valid_params)
      assert json_response_and_validate_schema(res, 200)

      [{127, 0, 0, 1}, {127, 0, 0, 2}, {127, 0, 0, 3}, {127, 0, 0, 4}]
      |> Stream.zip(Map.delete(valid_params, :email))
      |> Enum.each(fn {ip, {attr, _}} ->
        res =
          conn
          |> Map.put(:remote_ip, ip)
          |> post("/api/v1/accounts", Map.delete(valid_params, attr))
          |> json_response_and_validate_schema(400)

        assert res == %{
                 "error" => "Please review the submission",
                 "fields" => %{"#{attr}" => ["Missing field: #{attr}."]},
                 "identifier" => "review_submission"
               }
      end)
    end

    test "returns bad_request if missing email params when :account_activation_required is enabled",
         %{conn: conn, valid_params: valid_params} do
      clear_config([:instance, :account_activation_required], true)

      app_token = insert(:oauth_token, user: nil)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> app_token.token)
        |> put_req_header("content-type", "application/json")

      res =
        conn
        |> Map.put(:remote_ip, {127, 0, 0, 5})
        |> post("/api/v1/accounts", Map.delete(valid_params, :email))
        |> json_response_and_validate_schema(400)

      assert res == %{
               "error" => "Please review the submission",
               "fields" => %{"email" => ["Missing parameter: email"]},
               "identifier" => "review_submission"
             }

      res =
        conn
        |> Map.put(:remote_ip, {127, 0, 0, 6})
        |> post("/api/v1/accounts", Map.put(valid_params, :email, ""))
        |> json_response_and_validate_schema(400)

      assert res == %{
               "error" => "Please review the submission",
               "fields" => %{"email" => ["Email can't be blank"]},
               "identifier" => "review_submission"
             }
    end

    test "allow registration without an email", %{conn: conn, valid_params: valid_params} do
      app_token = insert(:oauth_token, user: nil)
      conn = put_req_header(conn, "authorization", "Bearer " <> app_token.token)

      res =
        conn
        |> put_req_header("content-type", "application/json")
        |> Map.put(:remote_ip, {127, 0, 0, 7})
        |> post("/api/v1/accounts", Map.delete(valid_params, :email))

      assert json_response_and_validate_schema(res, 200)
    end

    test "allow registration with an empty email", %{conn: conn, valid_params: valid_params} do
      app_token = insert(:oauth_token, user: nil)
      conn = put_req_header(conn, "authorization", "Bearer " <> app_token.token)

      res =
        conn
        |> put_req_header("content-type", "application/json")
        |> Map.put(:remote_ip, {127, 0, 0, 8})
        |> post("/api/v1/accounts", Map.put(valid_params, :email, ""))

      assert json_response_and_validate_schema(res, 200)
    end

    test "returns forbidden if token is invalid", %{conn: conn, valid_params: valid_params} do
      res =
        conn
        |> put_req_header("authorization", "Bearer " <> "invalid-token")
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v1/accounts", valid_params)

      assert json_response_and_validate_schema(res, 403) == %{"error" => "Invalid credentials"}
    end

    test "registration from trusted app" do
      clear_config([Pleroma.Captcha, :enabled], true)
      app = insert(:oauth_app, trusted: true, scopes: ["read", "write", "follow", "push"])

      conn =
        build_conn()
        |> post("/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => app.client_id,
          "client_secret" => app.client_secret
        })

      assert %{"access_token" => token, "token_type" => "Bearer"} = json_response(conn, 200)

      response =
        build_conn()
        |> Plug.Conn.put_req_header("authorization", "Bearer " <> token)
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v1/accounts", %{
          nickname: "nickanme",
          agreement: true,
          email: "email@example.com",
          fullname: "Lain",
          username: "Lain",
          password: "some_password",
          confirm: "some_password"
        })
        |> json_response_and_validate_schema(200)

      assert %{
               "access_token" => access_token,
               "created_at" => _,
               "scope" => "read write follow push",
               "token_type" => "Bearer"
             } = response

      response =
        build_conn()
        |> Plug.Conn.put_req_header("authorization", "Bearer " <> access_token)
        |> get("/api/v1/accounts/verify_credentials")
        |> json_response_and_validate_schema(200)

      assert %{
               "acct" => "Lain",
               "bot" => false,
               "display_name" => "Lain",
               "follow_requests_count" => 0,
               "followers_count" => 0,
               "following_count" => 0,
               "locked" => false,
               "note" => "",
               "source" => %{
                 "fields" => [],
                 "note" => "",
                 "pleroma" => %{
                   "actor_type" => "Person",
                   "discoverable" => false,
                   "no_rich_text" => false,
                   "show_role" => true
                 },
                 "privacy" => "public",
                 "sensitive" => false
               },
               "statuses_count" => 0,
               "username" => "Lain"
             } = response
    end
  end

  describe "create account by app / rate limit" do
    setup do: clear_config([:rate_limit, :app_account_creation], {10_000, 2})

    test "respects rate limit setting", %{conn: conn} do
      app_token = insert(:oauth_token, user: nil)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> app_token.token)
        |> Map.put(:remote_ip, {15, 15, 15, 15})
        |> put_req_header("content-type", "multipart/form-data")

      for i <- 1..2 do
        conn =
          conn
          |> post("/api/v1/accounts", %{
            username: "#{i}lain",
            email: "#{i}lain@example.org",
            password: "PlzDontHackLain",
            agreement: true
          })

        %{
          "access_token" => token,
          "created_at" => _created_at,
          "scope" => _scope,
          "token_type" => "Bearer"
        } = json_response_and_validate_schema(conn, 200)

        token_from_db = Repo.get_by(Token, token: token)
        assert token_from_db
        token_from_db = Repo.preload(token_from_db, :user)
        assert token_from_db.user
      end

      conn =
        post(conn, "/api/v1/accounts", %{
          username: "6lain",
          email: "6lain@example.org",
          password: "PlzDontHackLain",
          agreement: true
        })

      assert json_response_and_validate_schema(conn, :too_many_requests) == %{
               "error" => "Throttled"
             }
    end
  end

  describe "create account via invite" do
    setup %{conn: conn} do
      app_token = insert(:oauth_token, user: nil)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> app_token.token)
        |> put_req_header("content-type", "multipart/form-data")

      [conn: conn]
    end

    setup do: clear_config([:instance, :registrations_open], false)
    setup do: clear_config([Pleroma.Captcha, :enabled], false)

    test "creates an account", %{conn: conn} do
      invite = insert(:user_invite_token, %{invite_type: "one_time"})

      params = %{
        username: "lain",
        email: "lain@example.org",
        password: "PlzDontHackLain",
        agreement: true,
        token: invite.token
      }

      res =
        conn
        |> post("/api/v1/accounts", params)
        |> json_response_and_validate_schema(:ok)

      invite = Repo.get_by(UserInviteToken, token: invite.token)
      assert invite.used == true

      assert %{
               "access_token" => access_token,
               "created_at" => _,
               "scope" => "read",
               "token_type" => "Bearer"
             } = res

      user = Repo.get_by(Token, token: access_token) |> Repo.preload(:user) |> Map.get(:user)
      assert user.email == "lain@example.org"
    end

    test "returns error when already used", %{conn: conn} do
      invite = insert(:user_invite_token, %{used: true, invite_type: "one_time"})

      params = %{
        username: "lain",
        email: "lain@example.org",
        password: "PlzDontHackLain",
        agreement: true,
        token: invite.token
      }

      res =
        conn
        |> post("/api/v1/accounts", params)
        |> json_response_and_validate_schema(400)

      assert res == %{
               "error" => "Please review the submission",
               "fields" => %{"invite" => ["Expired token"]},
               "identifier" => "review_submission"
             }
    end

    test "returns errors when invite is invalid", %{conn: conn} do
      params = %{
        username: "lain",
        email: "lain@example.org",
        password: "PlzDontHackLain",
        agreement: true,
        token: "fake-token"
      }

      res =
        conn
        |> post("/api/v1/accounts", params)
        |> json_response_and_validate_schema(400)

      assert res == %{
               "error" => "Please review the submission",
               "fields" => %{"invite" => ["Invalid token"]},
               "identifier" => "review_submission"
             }
    end
  end

  describe "create account with enabled captcha" do
    setup %{conn: conn} do
      app_token = insert(:oauth_token, user: nil)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> app_token.token)
        |> put_req_header("content-type", "multipart/form-data")

      [conn: conn]
    end

    setup do: clear_config([Pleroma.Captcha, :enabled], true)

    test "creates an account and returns 200 if captcha is valid", %{conn: conn} do
      %{token: token, answer_data: answer_data} = Pleroma.Captcha.new()

      params = %{
        username: "lain",
        email: "lain@example.org",
        password: "PlzDontHackLain",
        agreement: true,
        captcha_solution: Pleroma.Captcha.Mock.solution(),
        captcha_token: token,
        captcha_answer_data: answer_data
      }

      assert %{
               "access_token" => access_token,
               "created_at" => _,
               "scope" => "read",
               "token_type" => "Bearer"
             } =
               conn
               |> post("/api/v1/accounts", params)
               |> json_response_and_validate_schema(:ok)

      assert Token |> Repo.get_by(token: access_token) |> Repo.preload(:user) |> Map.get(:user)

      Cachex.del(:used_captcha_cache, token)
    end

    test "returns 400 if any captcha field is not provided", %{conn: conn} do
      captcha_fields = [:captcha_solution, :captcha_token, :captcha_answer_data]

      valid_params = %{
        username: "lain",
        email: "lain@example.org",
        password: "PlzDontHackLain",
        agreement: true,
        captcha_solution: "xx",
        captcha_token: "xx",
        captcha_answer_data: "xx"
      }

      for field <- captcha_fields do
        expected = %{
          "error" => "Please review the submission",
          "fields" => %{"captcha" => ["Invalid CAPTCHA (Missing parameter: #{field})"]},
          "identifier" => "review_submission"
        }

        assert expected ==
                 conn
                 |> post("/api/v1/accounts", Map.delete(valid_params, field))
                 |> json_response_and_validate_schema(:bad_request)
      end
    end

    test "returns an error if captcha is invalid", %{conn: conn} do
      params = %{
        username: "lain",
        email: "lain@example.org",
        password: "PlzDontHackLain",
        agreement: true,
        captcha_solution: "cofe",
        captcha_token: "cofe",
        captcha_answer_data: "cofe"
      }

      assert %{
               "error" => "Please review the submission",
               "fields" => %{"captcha" => ["Invalid answer data"]},
               "identifier" => "review_submission"
             } ==
               conn
               |> post("/api/v1/accounts", params)
               |> json_response_and_validate_schema(:bad_request)
    end

    test "returns an error if captcha is valid and invite token invalid", %{conn: conn} do
      clear_config([:instance, :registrations_open], false)
      %{token: token, answer_data: answer_data} = Pleroma.Captcha.new()

      params = %{
        username: "lain",
        email: "lain@example.org",
        password: "PlzDontHackLain",
        agreement: true,
        token: "invite.token",
        captcha_solution: Pleroma.Captcha.Mock.solution(),
        captcha_token: token,
        captcha_answer_data: answer_data
      }

      assert %{
               "error" => "Please review the submission",
               "fields" => %{"invite" => ["Invalid token"]},
               "identifier" => "review_submission"
             } ==
               conn
               |> post("/api/v1/accounts", params)
               |> json_response_and_validate_schema(:bad_request)

      Cachex.del(:used_captcha_cache, token)
    end
  end

  describe "api spec errors" do
    setup %{conn: conn} do
      app_token = insert(:oauth_token, user: nil)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> app_token.token)
        |> put_req_header("content-type", "multipart/form-data")

      [conn: conn]
    end

    setup do: clear_config([:instance, :registrations_open], true)
    setup do: clear_config([Pleroma.Captcha, :enabled], false)

    test "returns errors when missed required field", %{conn: conn} do
      params = %{
        email: "lain@example.org",
        agreement: true
      }

      assert %{
               "error" => "Please review the submission",
               "fields" => %{
                 "password" => ["Missing field: password."],
                 "username" => ["Missing field: username."]
               },
               "identifier" => "review_submission"
             } ==
               conn
               |> post("/api/v1/accounts", params)
               |> json_response_and_validate_schema(:bad_request)
    end
  end
end
