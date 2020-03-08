# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.WebFinger.WebFingerControllerTest do
  use Pleroma.Web.ConnCase

  import ExUnit.CaptureLog
  import Pleroma.Factory
  import Tesla.Mock
  import SweetXml

  setup do
    mock(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  clear_config([Pleroma.Web.Endpoint, :web_endpoint])

  clear_config_all([:instance, :federating]) do
    Pleroma.Config.put([:instance, :federating], true)
  end

  describe "GET /.well-known/host-meta" do
    test "host-meta for set subdomain" do
      Pleroma.Config.put([Pleroma.Web.Endpoint, :web_endpoint], "http://pleroma.localhost")

      response =
        build_conn()
        |> get("/.well-known/host-meta")

      assert response.status == 200

      assert response.resp_body ==
               ~s(<?xml version="1.0" encoding="UTF-8"?><XRD xmlns="http://docs.oasis-open.org/ns/xri/xrd-1.0"><Link rel="lrdd" template="http://pleroma.localhost/.well-known/webfinger?resource={uri}" type="application/xrd+xml" /></XRD>)
    end

    test "host-meta for domain" do
      response =
        build_conn()
        |> get("/.well-known/host-meta")

      assert response.status == 200

      assert response.resp_body ==
               ~s(<?xml version="1.0" encoding="UTF-8"?><XRD xmlns="http://docs.oasis-open.org/ns/xri/xrd-1.0"><Link rel="lrdd" template="#{
                 Pleroma.Web.web_url()
               }/.well-known/webfinger?resource={uri}" type="application/xrd+xml" /></XRD>)
    end
  end

  describe "Webfinger JRD" do
    test "main domain" do
      user = insert(:user)

      response =
        build_conn()
        |> put_req_header("accept", "application/jrd+json")
        |> get("/.well-known/webfinger?resource=acct:#{user.nickname}@localhost")

      assert json_response(response, 200)["subject"] == "acct:#{user.nickname}@localhost"
    end

    test "for subdomain" do
      Pleroma.Config.put([Pleroma.Web.Endpoint, :web_endpoint], "http://pleroma.localhost")
      user = insert(:user)

      response =
        build_conn()
        |> put_req_header("accept", "application/jrd+json")
        |> get("/.well-known/webfinger?resource=acct:#{user.nickname}@pleroma.localhost")
        |> json_response(200)

      assert response["subject"] == "acct:#{user.nickname}@pleroma.localhost"
      assert response["aliases"] == [user.ap_id]

      assert response["links"] == [
               %{
                 "href" => user.ap_id,
                 "rel" => "http://webfinger.net/rel/profile-page",
                 "type" => "text/html"
               },
               %{"href" => user.ap_id, "rel" => "self", "type" => "application/activity+json"},
               %{
                 "href" => user.ap_id,
                 "rel" => "self",
                 "type" =>
                   "application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\""
               },
               %{
                 "rel" => "http://ostatus.org/schema/1.0/subscribe",
                 "template" => "http://pleroma.localhost/ostatus_subscribe?acct={uri}"
               }
             ]
    end

    test "it returns 404 when user isn't found (JSON)" do
      result =
        build_conn()
        |> put_req_header("accept", "application/jrd+json")
        |> get("/.well-known/webfinger?resource=acct:jimm@localhost")
        |> json_response(404)

      assert result == "Couldn't find user"
    end
  end

  describe "webfinger XML" do
    test "for subdomain" do
      Pleroma.Config.put([Pleroma.Web.Endpoint, :web_endpoint], "http://pleroma.localhost")
      user = insert(:user)

      response =
        build_conn()
        |> put_req_header("accept", "application/xrd+xml")
        |> get("/.well-known/webfinger?resource=acct:#{user.nickname}@pleroma.localhost")
        |> response(200)
        |> parse()

      assert xpath(response, ~x"//Subject/text()"s) == "acct:#{user.nickname}@pleroma.localhost"
    end

    test "for main domain" do
      user = insert(:user)

      response =
        build_conn()
        |> put_req_header("accept", "application/xrd+xml")
        |> get("/.well-known/webfinger?resource=acct:#{user.nickname}@localhost")
        |> response(200)
        |> parse()

      assert xpath(response, ~x"//Subject/text()"s) == "acct:#{user.nickname}@localhost"
    end

    test "it returns 404 when user isn't found (XML)" do
      result =
        build_conn()
        |> put_req_header("accept", "application/xrd+xml")
        |> get("/.well-known/webfinger?resource=acct:jimm@localhost")
        |> response(404)

      assert result == "Couldn't find user"
    end
  end

  test "Sends a 404 when invalid format" do
    user = insert(:user)

    assert capture_log(fn ->
             assert_raise Phoenix.NotAcceptableError, fn ->
               build_conn()
               |> put_req_header("accept", "text/html")
               |> get("/.well-known/webfinger?resource=acct:#{user.nickname}@localhost")
             end
           end) =~ "no supported media type in accept header"
  end

  test "Sends a 400 when resource param is missing" do
    response =
      build_conn()
      |> put_req_header("accept", "application/xrd+xml,application/jrd+json")
      |> get("/.well-known/webfinger")

    assert response(response, 400)
  end
end
