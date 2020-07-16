defmodule Pleroma.InstallerWeb.SetupControllerTest do
  use Pleroma.InstallerWeb.ConnCase

  @token "secret_token"

  setup do: clear_config(:installer_token, @token)

  setup do
    start_supervised(Pleroma.InstallerWeb.Endpoint)
    url = Pleroma.InstallerWeb.Endpoint.url()
    [url: url]
  end

  describe "index" do
    test "without token", %{conn: conn, url: url} do
      assert conn |> get(url) |> text_response(200) =~ "Token is invalid"
    end

    test "with token", %{conn: conn, url: url} do
      assert conn |> get(url <> "?token=#{@token}") |> html_response(200) =~
               "For Pleroma to work correctly"
    end
  end

  test "credentials", %{conn: conn, url: url} do
    assert conn |> get(url <> "/credentials?token=#{@token}") |> html_response(200) =~
             "Database Settings"
  end

  test "config", %{conn: conn, url: url} do
    assert conn |> get(url <> "/config?token=#{@token}") |> html_response(200) =~
             "What is the name of your instance?"
  end
end
