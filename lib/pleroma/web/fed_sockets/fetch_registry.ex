# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.FetchRegistry do
  @moduledoc """
  The FetchRegistry acts as a broker for fetch requests and return values.
  This allows calling processes to block while waiting for a reply.
  It doesn't impose it's own process instead using `Cachex` to handle fetches in process, allowing
  multi threaded processes to avoid bottlenecking.

  Normally outside modules will have no need to call or use the FetchRegistry themselves.

  The `Cachex` parameters can be controlled from the config. Since exact timeout intervals
  aren't necessary the following settings are used by default:

  config :pleroma, :fed_sockets,
    fed_socket_fetches: [
      default: 12_000,
      interval: 3_000,
      lazy: false
    ]

  """

  alias Ecto.UUID
  alias Pleroma.Web.FedSockets.FedSocket

  require Logger

  @fetches :fed_socket_fetches

  @type fetch_id :: Ecto.UUID.t()

  @doc "Synchronous version of `fetch_async/2`"
  @spec fetch(any(), pid(), pos_integer()) :: {:ok, any()} | {:error, :timeout}
  def fetch(socket_pid, data, timeout) do
    fetch_id = fetch_async(socket_pid, data)

    receive do
      {:fetch, ^fetch_id, response} -> {:ok, response}
    after
      timeout ->
        cancel(fetch_id)
        {:error, :timeout}
    end
  end

  @doc """
  Starts a fetch and returns it's id.
  Once a reply to a fetch is received, the following message is sent
  to the caller:
  `{:fetch, fetch_id, reply}`
  """
  @spec fetch_async(any(), pid()) :: fetch_id()
  def fetch_async(socket_pid, data) do
    send_to = self()
    uuid = UUID.generate()

    # Set up a sentinel process to cancel the fetch if the caller exits
    # before finishing the fetch (i.e the fetch was requested while processing
    # an http request, but the caller got killed because the client closed the
    # connection)
    sentinel =
      spawn(fn ->
        ref = Process.monitor(send_to)

        receive do
          {:DOWN, ^ref, _, _, _} -> cancel(uuid)
        end
      end)

    {:ok, true} = Cachex.put(@fetches, uuid, {send_to, sentinel})

    %{action: :fetch, data: data, uuid: uuid}
    |> Jason.encode!()
    |> FedSocket.send_packet(socket_pid)

    uuid
  end

  @doc "Removes the fetch from the registry. Any responses to it will be ignored afterwards."
  @spec cancel(fetch_id()) :: :ok
  def cancel(id) do
    {:ok, true} = Cachex.del(@fetches, id)
  end

  @doc "This is called to register a fetch has returned."
  @spec receive_callback(fetch_id(), any()) :: :ok
  def receive_callback(uuid, data) do
    case Cachex.get(@fetches, uuid) do
      {:ok, {caller, sentinel}} ->
        :ok = cancel(uuid)
        Process.exit(sentinel, :normal)
        send(caller, {:fetch, uuid, data})

      {:ok, nil} ->
        Logger.debug(fn ->
          "#{__MODULE__}: Got a reply to #{uuid}, but no such fetch is registered. This is probably a timeout."
        end)
    end

    :ok
  end
end
