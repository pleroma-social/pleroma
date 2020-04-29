defmodule Pleroma.HTTP.Middleware.FollowRedirectsTest do
  use ExUnit.Case

  import Mox

  alias Pleroma.Gun.Conn
  alias Pleroma.HTTP.Middleware.FollowRedirects
  alias Pleroma.Pool.Connections

  setup :verify_on_exit!
  setup :set_mox_global

  defp gun_mock do
    Pleroma.GunMock
    |> stub(:open, fn _, _, _ ->
      Task.start_link(fn -> Process.sleep(1000) end)
    end)
    |> stub(:await_up, fn _, _ -> {:ok, :http} end)
    |> stub(:set_owner, fn _, _ -> :ok end)

    :ok
  end

  setup do
    gun_mock()

    env = %Tesla.Env{
      body: "",
      headers: [
        {"user-agent", "Pleroma"}
      ],
      method: :get,
      opts: [
        adapter: [
          pool: :media,
          reuse_conn: true
        ]
      ]
    }

    {:ok, env: env}
  end

  defmodule NoRedirect do
    def call(env, _opts) do
      opts = env.opts[:adapter]
      assert opts[:reuse_conn]
      assert opts[:conn]
      assert opts[:close_conn] == false

      {:ok, %{env | status: 200, body: opts[:conn]}}
    end
  end

  describe "checkin/checkout conn without redirects" do
    setup do
      next = [{NoRedirect, :call, [[]]}]
      {:ok, next: next}
    end

    test "common", %{env: env, next: next} do
      env = %{env | url: "https://common.com/media/common.jpg"}
      assert {:ok, %{body: conn}} = FollowRedirects.call(env, next)

      assert match?(
               %Connections{
                 conns: %{
                   "https:common.com:443" => %Conn{
                     awaited_by: [],
                     conn: ^conn,
                     conn_state: :idle,
                     gun_state: :up,
                     retries: 0,
                     used_by: []
                   }
                 }
               },
               Connections.get_state(:gun_connections)
             )
    end

    test "reverse proxy call", %{env: env, next: next} do
      env =
        put_in(env.opts[:adapter][:body_as], :chunks)
        |> Map.put(:url, "https://chunks.com/media/chunks.jpg")

      assert {:ok, %{body: conn}} = FollowRedirects.call(env, next)

      self = self()

      assert match?(
               %Connections{
                 conns: %{
                   "https:chunks.com:443" => %Conn{
                     awaited_by: [],
                     conn: ^conn,
                     conn_state: :active,
                     gun_state: :up,
                     retries: 0,
                     used_by: [{^self, _}]
                   }
                 }
               },
               Connections.get_state(:gun_connections)
             )
    end
  end

  defmodule OneRedirect do
    def call(%{url: "https://first-redirect.com"} = env, _opts) do
      opts = env.opts[:adapter]
      assert opts[:reuse_conn]
      assert opts[:conn]
      assert opts[:close_conn] == false

      {:ok, %{env | status: 302, body: opts[:conn], headers: [{"location", opts[:final_url]}]}}
    end

    def call(env, _opts) do
      opts = env.opts[:adapter]
      assert opts[:reuse_conn]
      assert opts[:conn]
      assert opts[:close_conn] == false

      {:ok, %{env | status: 200, body: opts[:conn]}}
    end
  end

  describe "checkin/checkout with 1 redirect" do
    setup do
      next = [{OneRedirect, :call, [[]]}]

      {:ok, next: next}
    end

    test "common with redirect", %{env: env, next: next} do
      adapter_opts = Keyword.put(env.opts[:adapter], :final_url, "https://another-final-url.com")

      env =
        put_in(env.opts[:adapter], adapter_opts)
        |> Map.put(:url, "https://first-redirect.com")

      assert {:ok, %{body: conn}} = FollowRedirects.call(env, next)

      assert match?(
               %Connections{
                 conns: %{
                   "https:first-redirect.com:443" => %Conn{
                     awaited_by: [],
                     conn: _,
                     conn_state: :idle,
                     gun_state: :up,
                     retries: 0,
                     used_by: []
                   },
                   "https:another-final-url.com:443" => %Conn{
                     awaited_by: [],
                     conn: ^conn,
                     conn_state: :idle,
                     gun_state: :up,
                     retries: 0,
                     used_by: []
                   }
                 }
               },
               Connections.get_state(:gun_connections)
             )
    end

    test "reverse proxy with redirect", %{env: env, next: next} do
      adapter_opts =
        Keyword.merge(env.opts[:adapter], body_as: :chunks, final_url: "https://final-url.com")

      env =
        put_in(env.opts[:adapter], adapter_opts)
        |> Map.put(:url, "https://first-redirect.com")

      assert {:ok, %{body: conn}} = FollowRedirects.call(env, next)

      self = self()

      assert match?(
               %Connections{
                 conns: %{
                   "https:first-redirect.com:443" => %Conn{
                     awaited_by: [],
                     conn: _,
                     conn_state: :idle,
                     gun_state: :up,
                     retries: 0,
                     used_by: []
                   },
                   "https:final-url.com:443" => %Conn{
                     awaited_by: [],
                     conn: ^conn,
                     conn_state: :active,
                     gun_state: :up,
                     retries: 0,
                     used_by: [{^self, _}]
                   }
                 }
               },
               Connections.get_state(:gun_connections)
             )
    end
  end

  defmodule TwoRedirect do
    def call(%{url: "https://1-redirect.com"} = env, _opts) do
      opts = env.opts[:adapter]
      assert opts[:reuse_conn]
      assert opts[:conn]
      assert opts[:close_conn] == false

      {:ok,
       %{env | status: 302, body: opts[:conn], headers: [{"location", "https://2-redirect.com"}]}}
    end

    def call(%{url: "https://2-redirect.com"} = env, _opts) do
      opts = env.opts[:adapter]
      assert opts[:reuse_conn]
      assert opts[:conn]
      assert opts[:close_conn] == false

      {:ok, %{env | status: 302, body: opts[:conn], headers: [{"location", opts[:final_url]}]}}
    end

    def call(env, _opts) do
      opts = env.opts[:adapter]
      assert opts[:reuse_conn]
      assert opts[:conn]
      assert opts[:close_conn] == false

      {:ok, %{env | status: 200, body: opts[:conn]}}
    end
  end

  describe "checkin/checkout conn with max redirects" do
    setup do
      next = [{TwoRedirect, :call, [[]]}]
      {:ok, next: next}
    end

    test "common with max redirects", %{env: env, next: next} do
      adapter_opts =
        Keyword.merge(env.opts[:adapter],
          final_url: "https://some-final-url.com"
        )

      env =
        put_in(env.opts[:adapter], adapter_opts)
        |> Map.put(:url, "https://1-redirect.com")

      assert match?(
               {:error, {FollowRedirects, :too_many_redirects}},
               FollowRedirects.call(env, next, max_redirects: 1)
             )

      assert match?(
               %Connections{
                 conns: %{
                   "https:1-redirect.com:443" => %Conn{
                     awaited_by: [],
                     conn: _,
                     conn_state: :idle,
                     gun_state: :up,
                     retries: 0,
                     used_by: []
                   },
                   "https:2-redirect.com:443" => %Conn{
                     awaited_by: [],
                     conn: _,
                     conn_state: :idle,
                     gun_state: :up,
                     retries: 0,
                     used_by: []
                   }
                 }
               },
               Connections.get_state(:gun_connections)
             )
    end
  end
end
