# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.DomainMuteControllerTest do
  use Pleroma.Web.ConnCase, async: true

  import Pleroma.Factory

  alias Pleroma.User

  test "muting / unmuting domain" do
    %{user: user, conn: conn} = oauth_access(["write:mutes", "read:mutes"])
    conn = put_req_header(conn, "content-type", "application/json")

    other_user = insert(:user, ap_id: "https://example.com/users/other_user")

    response = post(conn, "/api/pleroma/domain_mutes", %{"domain" => "example.com"})

    assert %{} == json_response_and_validate_schema(response, 200)
    user = User.get_cached_by_ap_id(user.ap_id)
    assert User.mutes?(user, other_user)
    assert User.mutes_domain?(user, other_user)

    assert ["example.com"] ==
             conn
             |> assign(:user, user)
             |> get("/api/pleroma/domain_mutes")
             |> json_response_and_validate_schema(200)

    response = delete(conn, "/api/pleroma/domain_mutes", %{"domain" => "example.com"})

    assert %{} == json_response_and_validate_schema(response, 200)
    user = User.get_cached_by_ap_id(user.ap_id)
    refute User.mutes?(user, other_user)
    refute User.mutes_domain?(user, other_user)

    assert [] ==
             conn
             |> assign(:user, user)
             |> get("/api/pleroma/domain_mutes")
             |> json_response_and_validate_schema(200)
  end
end
