# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.ReverseProxyClientCase do
  defmacro __using__(client: client) do
    quote do
      use ExUnit.Case
      @moduletag :integration
      @client unquote(client)

      setup do
        Application.put_env(:tesla, :adapter, Tesla.Adapter.Gun)
        on_exit(fn -> Application.put_env(:tesla, :adapter, Tesla.Mock) end)
      end

      test "get response body stream" do
        {:ok, status, headers, ref} =
          @client.request(
            :get,
            "http://httpbin.org/stream-bytes/10",
            [{"accept", "application/octet-stream"}],
            "",
            []
          )

        assert status == 200
        assert headers != []

        {:ok, response, ref} = @client.stream_body(ref)
        check_ref(ref)
        assert is_binary(response)
        assert byte_size(response) == 10

        assert :done == @client.stream_body(ref)
      end

      test "head response" do
        {:ok, status, headers} = @client.request(:head, "http://httpbin.org/get", [], "", [])

        assert status == 200
        assert headers != []
      end

      test "get error response" do
        case @client.request(
               :get,
               "http://httpbin.org/status/500",
               [],
               "",
               []
             ) do
          {:ok, status, headers, ref} ->
            assert status == 500
            assert headers != []
            check_ref(ref)

            assert :ok == close(ref)

          {:ok, status, headers} ->
            assert headers != []
        end
      end

      test "head error response" do
        {:ok, status, headers} =
          @client.request(
            :head,
            "http://httpbin.org/status/500",
            [],
            "",
            []
          )

        assert status == 500
        assert headers != []
      end
    end
  end
end
