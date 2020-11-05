# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.EctoHelperTest do
  use Pleroma.DataCase

  describe "pretty_errors/2" do
    test "returns errors messages" do
      errors = [
        name:
          {"should be at least %{count} character(s)",
           [count: 5, validation: :length, kind: :min, type: :string]},
        name: {"has invalid format", [validation: :format]}
      ]

      assert Pleroma.EctoHelper.pretty_errors(errors) == %{
               name: ["Name should be at least 5 character(s)", "Name has invalid format"]
             }
    end

    test "returns errors messages with mapping field" do
      errors = [
        name:
          {"should be at least %{count} character(s)",
           [count: 5, validation: :length, kind: :min, type: :string]},
        name: {"has invalid format", [validation: :format]}
      ]

      assert Pleroma.EctoHelper.pretty_errors(errors, %{name: "Username"}) == %{
               name: ["Username should be at least 5 character(s)", "Username has invalid format"]
             }
    end
  end
end
