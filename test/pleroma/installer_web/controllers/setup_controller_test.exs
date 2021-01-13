defmodule Pleroma.InstallerWeb.SetupControllerTest do
  use Pleroma.InstallerWeb.ConnCase

  import ExUnit.CaptureLog
  import Mox

  alias Pleroma.Installer.CallbacksMock
  alias Pleroma.Repo

  setup :verify_on_exit!

  @token "secret_token"
  @psql_path "/tmp/setup_db.psql"
  @test_config "config/test_installer.secret.exs"

  setup do: clear_config(:config_path_in_test, @test_config)
  setup do: clear_config(:installer_token, @token)

  defp token(%{conn: conn}), do: [conn: init_test_session(conn, %{token: @token})]

  defp revert do
    psql =
      EEx.eval_file(
        "test/fixtures/installer/revert_psql.eex",
        database: "pleroma_installer",
        username: "pleroma_installer"
      )

    psql_file = "/tmp/revert.psql"

    File.write!(psql_file, psql)

    # TODO: make configurable for every env
    System.cmd("psql", ["-f", psql_file])

    File.rm!(psql_file)
  end

  defp credentials(_) do
    config = Repo.config()

    credentials = %{
      database: "pleroma_installer",
      username: "pleroma_installer",
      password: "password",
      rum_enabled: false,
      hostname: Keyword.fetch!(config, :hostname),
      pool_size: 2
    }

    [credentials: credentials]
  end

  describe "GET /" do
    test "without token", %{conn: conn} do
      assert conn |> get("/") |> text_response(200) =~ "Token is invalid"
    end

    test "with token", %{conn: conn} do
      assert conn |> get("/?token=#{@token}") |> html_response(200) =~
               "Database Settings"
    end
  end

  describe "POST `/credentials` errors" do
    setup :token
    setup :credentials

    test "invalid params", %{conn: conn} do
      assert conn
             |> post("/credentials", %{
               credentials_form: %{database: "", username: "", password: ""}
             })
             |> html_response(200) =~ "can&#39;t be blank"
    end

    test "file save error", %{conn: conn, credentials: credentials} do
      expect(CallbacksMock, :write, fn _, _ -> {:error, :enospc} end)

      capture_log(fn ->
        assert conn
               |> post("/credentials", %{
                 credentials_form: credentials
               })
               |> html_response(200) =~
                 "Error occuried: :enospc"
      end) =~ "[error]"
    end

    test "executing psql file error", %{conn: conn, credentials: credentials} do
      clear_config(:credentials)

      CallbacksMock
      |> expect(:write, fn _, _ -> :ok end)
      |> expect(:execute_psql_file, fn _ -> {"", 1} end)

      capture_log(fn ->
        assert conn
               |> post("/credentials", %{
                 credentials_form: credentials
               })
               |> html_response(200) =~ "Run following command to setup PostgreSQL"
      end) =~ "Writing the postgres script to /tmp/setup_db.psql"

      assert Pleroma.Config.get(:credentials) ==
               credentials |> Map.put(:pool_size, 2) |> Keyword.new()
    end

    test "db connection error", %{conn: conn, credentials: credentials} do
      CallbacksMock
      |> expect(:write, fn _, _ -> :ok end)
      |> expect(:execute_psql_file, fn _ -> {"", 0} end)
      |> expect(:start_dynamic_repo, fn _ -> {:ok, nil} end)
      |> expect(:check_connection, fn -> {:error, %DBConnection.ConnectionError{}} end)

      capture_log(fn ->
        assert conn
               |> post("/credentials", %{
                 credentials_form: credentials
               })
               |> html_response(200) =~
                 "Error occuried: Pleroma can&#39;t connect to the database with these credentials. Please check them and try one more time."
      end) =~ "[error]"
    end
  end

  describe "POST /credentials" do
    setup :token
    setup :credentials

    setup do
      CallbacksMock
      |> expect(:write, fn _, _ -> :ok end)
      |> expect(:execute_psql_file, fn _ -> {"", 0} end)
      |> expect(:start_dynamic_repo, fn _ -> {:ok, nil} end)
      |> expect(:check_connection, fn -> {:ok, nil} end)
      |> expect(:check_extensions, fn _ -> :ok end)

      on_exit(fn ->
        File.rm!(@test_config)
      end)
    end

    test "saves credentials", %{conn: conn, credentials: credentials} do
      assert conn
             |> post("/credentials", %{
               credentials_form: credentials
             })
             |> redirected_to() =~ "/migrations"

      assert File.exists?(@test_config)
    end

    test "generates password and saved credentials", %{conn: conn, credentials: credentials} do
      assert conn
             |> post("/credentials", %{
               credentials_form: Map.put(credentials, :password, "")
             })
             |> redirected_to() =~ "/migrations"

      assert File.exists?(@test_config)
    end
  end

  describe "GET /check_database_and_write_config" do
    setup :token
    setup :credentials

    setup do: clear_config(:credentials)

    setup do
      expect(CallbacksMock, :start_dynamic_repo, fn _ -> {:ok, nil} end)

      :ok
    end

    test "db connection error", %{conn: conn, credentials: credentials} do
      expect(CallbacksMock, :check_connection, fn -> {:error, %DBConnection.ConnectionError{}} end)

      Pleroma.Config.put(:credentials, Keyword.new(credentials))

      assert conn |> get("/check_database_and_write_config") |> html_response(200) =~
               "Are you sure psql file was executed?"
    end

    test "another error", %{conn: conn, credentials: credentials} do
      error_msg = "These extensions are not installed: rum"

      expect(CallbacksMock, :check_connection, fn -> {:error, error_msg} end)

      Pleroma.Config.put(:credentials, Keyword.new(credentials))

      assert conn |> get("/check_database_and_write_config") |> html_response(200) =~
               error_msg
    end

    test "writes config file", %{conn: conn, credentials: credentials} do
      CallbacksMock
      |> expect(:check_connection, fn -> {:ok, nil} end)
      |> expect(:check_extensions, fn _ -> :ok end)

      Pleroma.Config.put(:credentials, Keyword.new(credentials))

      assert conn |> get("/check_database_and_write_config") |> redirected_to() =~ "/migrations"

      assert File.exists?(@test_config)

      on_exit(fn ->
        File.rm!(@test_config)
      end)
    end
  end

  describe "GET /run_migrations" do
    setup :token

    test "with error", %{conn: conn} do
      CallbacksMock
      |> expect(:start_dynamic_repo, fn _ -> {:ok, nil} end)
      |> expect(:run_migrations, fn _, _ -> [] end)

      assert conn |> get("/run_migrations") |> json_response(200) ==
               "Error occuried while migrations were run."
    end

    test "success", %{conn: conn} do
      CallbacksMock
      |> expect(:start_dynamic_repo, fn _ -> {:ok, nil} end)
      |> expect(:run_migrations, fn _, _ -> [1] end)

      assert conn |> get("/run_migrations") |> json_response(200) == "ok"
    end
  end

  describe "GET /migrations" do
    setup :token

    test "", %{conn: conn} do
      assert conn |> get("/migrations") |> html_response(200) =~
               "The database is almost ready. Migrations are running."
    end
  end

  describe "GET /config" do
    setup :token

    test "config", %{conn: conn} do
      assert conn |> get("/config") |> html_response(200) =~
               "What is the name of your instance?"
    end
  end

  describe "POST /config" do
    setup :token

    test "validation error", %{conn: conn} do
      assert conn
             |> post("/config", %{
               config_form: %{
                 instance_static_dir: "instance/static",
                 endpoint_url_port: 443,
                 endpoint_http_ip: "127.0.0.1",
                 endpoint_http_port: 4000,
                 local_uploads_dir: "uploads"
               }
             })
             |> html_response(200) =~ "can&#39;t be blank"
    end

    test "config file not found error", %{conn: conn} do
      assert conn
             |> post("/config", %{
               config_form: %{
                 instance_static_dir: "instance/static",
                 endpoint_url: "https://example.com",
                 endpoint_http_ip: "127.0.0.1",
                 endpoint_http_port: 4000,
                 local_uploads_dir: "uploads",
                 instance_name: "test",
                 instance_email: "test@example.com",
                 instance_notify_email: "test@example.com"
               }
             })
             |> html_response(200) =~ "Error occuried: Something went wrong."
    end

    test "file write error", %{conn: conn} do
      File.touch(@test_config)
      expect(CallbacksMock, :write, fn _, _, _ -> {:error, :enospc} end)

      assert conn
             |> post("/config", %{
               config_form: %{
                 instance_static_dir: "instance/static",
                 endpoint_url: "https://example.com",
                 endpoint_http_ip: "127.0.0.1",
                 endpoint_http_port: 4000,
                 local_uploads_dir: "uploads",
                 instance_name: "test",
                 instance_email: "test@example.com",
                 instance_notify_email: "test@example.com"
               }
             })
             |> html_response(200) =~ "Error occuried: :enospc"

      on_exit(fn -> File.rm!(@test_config) end)
    end

    test "saving instance config", %{conn: conn} do
      assert Pleroma.Config.get(:installer_token) == @token

      File.touch(@test_config)

      CallbacksMock
      |> expect(:start_dynamic_repo, fn _ -> {:ok, nil} end)
      |> expect(:write, fn _, _, _ -> :ok end)

      static_dir = Pleroma.Config.get([:instance, :static_dir])

      ExUnit.CaptureIO.capture_io(fn ->
        assert conn
               |> post("/config", %{
                 config_form: %{
                   instance_static_dir: static_dir,
                   endpoint_url: "https://example.com",
                   endpoint_http_ip: "127.0.0.1",
                   endpoint_http_port: 4000,
                   local_uploads_dir: "uploads",
                   instance_name: "test",
                   instance_email: "test@example.com",
                   instance_notify_email: "test@example.com"
                 }
               })
               |> redirected_to() =~ Pleroma.Web.Endpoint.url()
      end) =~ "Writing test/instance_static/robots.txt."

      on_exit(fn ->
        File.rm!(@test_config)
        File.rm!(static_dir <> "/robots.txt")
      end)
    end
  end

  # TODO: add part for last writing to file part
  describe "integration" do
    setup :token
    setup :credentials

    setup do
      CallbacksMock
      |> expect(:write, fn psql_path, psql ->
        File.write(psql_path, psql)
      end)
      |> expect(:start_dynamic_repo, 2, fn credentials ->
        Pleroma.Installer.Callbacks.start_dynamic_repo(credentials)
      end)
      |> expect(:check_connection, fn -> {:ok, nil} end)
      |> expect(:check_extensions, fn rum_enabled? ->
        Pleroma.Installer.Callbacks.check_extensions(rum_enabled?)
      end)
      |> expect(:run_migrations, fn paths, repo ->
        Ecto.Migrator.run(Pleroma.Repo, paths, :up, all: true, dynamic_repo: repo)
      end)

      on_exit(fn ->
        File.rm!(@test_config)
        File.rm!(@psql_path)
        revert()
      end)
    end

    test "correct credentials", %{conn: conn, credentials: credentials} do
      expect(CallbacksMock, :execute_psql_file, fn file_path ->
        # TODO: make configurable in different environments
        System.cmd("psql", ["-f", file_path])
      end)

      assert conn
             |> post("/credentials", %{
               credentials_form: credentials
             })
             |> redirected_to() =~ "/migrations"

      assert File.exists?(@test_config)
      assert File.exists?(@psql_path)

      capture_log(fn ->
        assert conn |> get("/run_migrations") |> json_response(200) == "ok"
      end) =~ "ATTENTION ATTENTION ATTENTION"

      assert Repo
             |> Ecto.Migrator.migrations([Ecto.Migrator.migrations_path(Repo)],
               dynamic_repo: Pleroma.InstallerWeb.Forms.CredentialsForm.installer_repo()
             )
             |> Enum.reject(fn {dir, _, _} -> dir == :up end) == []

      assert Pleroma.Config.get(:credentials) ==
               credentials |> Map.put(:pool_size, 2) |> Keyword.new()
    end

    test "execution psql file error", %{conn: conn, credentials: credentials} do
      expect(CallbacksMock, :execute_psql_file, fn _ -> {"", 1} end)

      capture_log(fn ->
        assert conn
               |> post("/credentials", %{
                 credentials_form: credentials
               })
               |> html_response(200) =~ "Run following command to setup PostgreSQL"
      end) =~ "Writing the postgres script to /tmp/setup_db.psql"

      refute File.exists?(@test_config)

      assert File.exists?(@psql_path)
      System.cmd("psql", ["-f", @psql_path])

      assert conn |> get("/check_database_and_write_config") |> redirected_to() =~
               "/migrations"

      assert File.exists?(@test_config)

      capture_log(fn ->
        assert conn |> get("/run_migrations") |> json_response(200) == "ok"
      end) =~ "ATTENTION ATTENTION ATTENTION"

      assert Repo
             |> Ecto.Migrator.migrations([Ecto.Migrator.migrations_path(Repo)],
               dynamic_repo: Pleroma.InstallerWeb.Forms.CredentialsForm.installer_repo()
             )
             |> Enum.reject(fn {dir, _, _} -> dir == :up end) == []

      assert Pleroma.Config.get(:credentials) ==
               credentials |> Map.put(:pool_size, 2) |> Keyword.new()
    end
  end
end
