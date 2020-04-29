# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP.ConnectionTest do
  use ExUnit.Case

  alias Pleroma.HTTP.Connection

  describe "format_host/1" do
    test "as atom to charlist" do
      assert Connection.format_host(:localhost) == 'localhost'
    end

    test "as string to charlist" do
      assert Connection.format_host("localhost.com") == 'localhost.com'
    end

    test "as string ip to tuple" do
      assert Connection.format_host("127.0.0.1") == {127, 0, 0, 1}
    end
  end

  describe "options/2" do
    test "defaults" do
      assert Connection.options(%URI{}) == [env: :test, pool: :federation]
    end

    test "passed opts have more weight than defaults" do
      assert Connection.options(%URI{}, pool: :media) == [env: :test, pool: :media]
    end

    test "adding defaults for hackney adapter" do
      initial = Application.get_env(:tesla, :adapter)
      Application.put_env(:tesla, :adapter, Tesla.Adapter.Hackney)
      on_exit(fn -> Application.put_env(:tesla, :adapter, initial) end)

      refute %URI{scheme: "https", host: "example.com"}
             |> Connection.options()
             |> Keyword.delete(:pool) == []
    end

    test "adding defaults for gun adapter" do
      initial = Application.get_env(:tesla, :adapter)
      Application.put_env(:tesla, :adapter, Tesla.Adapter.Gun)
      on_exit(fn -> Application.put_env(:tesla, :adapter, initial) end)

      refute %URI{scheme: "https", host: "example.com"}
             |> Connection.options()
             |> Keyword.delete(:pool) == []
    end
  end
end
