defmodule Pleroma.FrontendTest do
  use Pleroma.DataCase

  describe "get_primary_fe_opts" do
    setup do: clear_config([:frontends])

    test "normal" do
      conf = %{primary: %{"name" => "testfe", "ref" => "test"}, static: false}
      Pleroma.Config.put([:frontends], conf)

      expected = %{
        config: conf[:primary],
        controller: Pleroma.Web.Frontend.TestfeController,
        static: conf[:static]
      }

      assert Pleroma.Frontend.get_primary_fe_opts() == expected
      assert Pleroma.Frontend.get_primary_fe_opts(conf) == expected
    end

    test "headless" do
      conf = %{primary: %{"name" => "none"}, static: false}
      Pleroma.Config.put([:frontends], conf)

      expected = %{
        config: %{},
        controller: Pleroma.Web.Frontend.HeadlessController,
        static: conf[:static]
      }

      assert Pleroma.Frontend.get_primary_fe_opts() == expected
    end
  end
end
