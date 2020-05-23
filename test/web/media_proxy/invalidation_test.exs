defmodule Pleroma.Web.MediaProxy.InvalidationTest do
  use ExUnit.Case
  use Pleroma.Tests.Helpers

  alias Pleroma.Config
  alias Pleroma.Web.MediaProxy.Invalidation

  import ExUnit.CaptureLog
  import Mock
  import Tesla.Mock

  setup do: clear_config([:media_proxy])

  describe "Invalidation.Http" do
    test "perform request to clear cache" do
      Config.put([:media_proxy, :invalidation, :enabled], true)
      Config.put([:media_proxy, :invalidation, :provider], Invalidation.Http)

      Config.put([Invalidation.Http], method: :purge, headers: [{"x-refresh", 1}])

      mock(fn
        %{
          method: :purge,
          url: "http://example.com/media/example.jpg",
          headers: [{"x-refresh", 1}]
        } ->
          %Tesla.Env{status: 200}
      end)

      assert capture_log(fn ->
               assert Invalidation.purge(["http://example.com/media/example.jpg"]) ==
                        {:ok, "success"}
             end) =~ "Running cache purge: [\"http://example.com/media/example.jpg\"]"
    end
  end

  describe "Invalidation.Script" do
    test "run script to clear cache" do
      Config.put([:media_proxy, :invalidation, :enabled], true)
      Config.put([:media_proxy, :invalidation, :provider], Invalidation.Script)
      Config.put([Invalidation.Script], script_path: "purge-nginx")

      with_mocks [{System, [], [cmd: fn _, _ -> {"ok", 0} end]}] do
        assert capture_log(fn ->
                 assert Invalidation.purge(["http://example.com/media/example.jpg"]) ==
                          {:ok, "success"}
               end) =~ "Running cache purge: [\"http://example.com/media/example.jpg\"]"
      end
    end
  end
end
