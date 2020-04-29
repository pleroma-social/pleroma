defmodule Pleroma.UtilsTest do
  use ExUnit.Case

  describe "command_available?" do
    test "available command" do
      assert Pleroma.Utils.command_available?("iex") === true
    end

    test "unavailable command" do
      assert Pleroma.Utils.command_available?("nonexistingcmd") === false
    end
  end
end
