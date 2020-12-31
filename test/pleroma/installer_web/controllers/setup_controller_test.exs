defmodule Pleroma.InstallerWeb.SetupControllerTest do
  use Pleroma.InstallerWeb.ConnCase

  import ExUnit.CaptureLog
  import Mox

  alias Pleroma.Installer.SystemMock
  alias Pleroma.Repo

  setup :verify_on_exit!

  @token "secret_token"

  setup_all do: clear_config(:installer_token, @token)

  describe "index" do
    test "without token", %{conn: conn} do
      assert conn |> get("/") |> text_response(200) =~ "Token is invalid"
    end

    test "with token", %{conn: conn} do
      assert conn |> get("/?token=#{@token}") |> html_response(200) =~
               "Database Settings"
    end
  end

  test "credentials save with invalid params", %{conn: conn} do
    resp =
      post(conn, "/credentials?token=#{@token}", %{
        credentials_form: %{database: "", username: "", password: ""}
      })

    assert html_response(resp, 200) =~ "can&#39;t be blank"
  end

  describe "prepare database" do
    @psql_path "/tmp/setup_db.psql"
    @test_config "config/test.secret.exs"

    setup :token
    setup do: clear_config(Repo)

    setup do
      credentials =
        Repo.config()
        |> Keyword.take([:hostname])
        |> Keyword.merge(
          database: "pleroma_installer",
          username: "pleroma_installer",
          password: "password",
          rum_enabled: false
        )
        |> Map.new()

      [credentials: credentials]
    end

    test "writes credentials to file", %{conn: conn, credentials: credentials} do
      expect(SystemMock, :execute_psql_file, fn file_path ->
        System.cmd("psql", ["-f", file_path])
      end)

      resp =
        post(conn, "/credentials", %{
          credentials_form: credentials
        })

      assert redirected_to(resp) =~ "/migrations"

      assert File.exists?(@test_config)
      assert File.exists?(@psql_path)

      capture_log(fn ->
        assert conn |> get("/run_migrations") |> json_response(200) == "ok"
      end) =~ "ATTENTION ATTENTION ATTENTION"

      assert_migrations()

      on_exit(fn ->
        File.rm!(@test_config)
        File.rm!(@psql_path)
        revert()
      end)
    end

    test "with db setup and generated password", %{conn: conn, credentials: credentials} do
      expect(SystemMock, :execute_psql_file, fn file_path ->
        System.cmd("psql", ["-f", file_path])
      end)

      resp =
        post(conn, "/credentials", %{
          credentials_form: Map.put(credentials, :password, "")
        })

      assert redirected_to(resp) =~ "/migrations"

      assert File.exists?(@psql_path)
      assert File.exists?(@test_config)

      capture_log(fn ->
        assert conn |> get("/run_migrations") |> json_response(200) == "ok"
      end) =~ "ATTENTION ATTENTION ATTENTION"

      assert_migrations()

      on_exit(fn ->
        File.rm!(@psql_path)
        File.rm!(@test_config)

        revert()
      end)
    end

    test "with db setup and executing psql file error", %{conn: conn, credentials: credentials} do
      expect(SystemMock, :execute_psql_file, fn _ -> {"", 1} end)

      capture_log(fn ->
        resp =
          post(conn, "/credentials", %{
            credentials_form: credentials
          })

        assert html_response(resp, 200) =~ "Run following command to setup PostgreSQL"
      end) =~ "Writing the postgres script to /tmp/setup_db.psql"

      assert File.exists?(@psql_path)

      assert Pleroma.Config.get(:credentials) ==
               credentials |> Map.put(:pool_size, 2) |> Map.to_list()

      refute File.exists?(@test_config)

      System.cmd("psql", ["-f", "/tmp/setup_db.psql"])

      resp = get(conn, "/check_database_and_write_config")

      refute Pleroma.Config.get(:credentials)
      assert redirected_to(resp) =~ "/migrations"
      assert File.exists?(@test_config)

      capture_log(fn ->
        assert conn |> get("/run_migrations") |> json_response(200) == "ok"
      end) =~ "ATTENTION ATTENTION ATTENTION"

      assert_migrations()
      # TODO: check that repo has generated config
      on_exit(fn ->
        File.rm!(@psql_path)
        File.rm!(@test_config)

        revert()
      end)
    end

    defp revert do
      psql =
        EEx.eval_file(
          "test/fixtures/installer/revert_psql.eex",
          database: "pleroma_installer",
          username: "pleroma_installer"
        )

      psql_path = "/tmp/revert.psql"

      File.write(psql_path, psql)

      System.cmd("psql", ["-f", psql_path])

      File.rm!(psql_path)
    end

    defp assert_migrations do
      assert Repo
             |> Ecto.Migrator.migrations([Ecto.Migrator.migrations_path(Repo)],
               dynamic_repo: Pleroma.InstallerWeb.Forms.CredentialsForm.installer_repo()
             )
             |> Enum.reject(fn {dir, _, _} -> dir == :up end) == []
    end
  end

  describe "migrations" do
    setup :token

    test "", %{conn: conn} do
      assert conn |> get("/migrations") |> html_response(200) =~
               "The database is almost ready. Migrations running."
    end
  end

  describe "config" do
    setup :token

    test "config", %{conn: conn} do
      assert conn |> get("/config") |> html_response(200) =~
               "What is the name of your instance?"
    end
  end

  defp token(%{conn: conn}), do: [conn: init_test_session(conn, %{token: @token})]
end
