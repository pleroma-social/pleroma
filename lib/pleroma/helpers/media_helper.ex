# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Helpers.MediaHelper do
  @moduledoc """
  Handles common media-related operations.
  """

  alias Pleroma.HTTP
  alias Pleroma.ReverseProxy

  @tmp_base "/tmp/pleroma-media_preview-pipe"

  def image_resize(url, options) do
    with executable when is_binary(executable) <- System.find_executable("convert"),
         {:ok, args} <- prepare_image_resize_args(options),
         {:ok, env} <- HTTP.get(url, [], pool: :media),
         {:ok, fifo_path} <- mkfifo() do
      args = List.flatten([fifo_path, args])
      run_fifo(fifo_path, env, executable, args)
    else
      nil -> {:error, {:convert, :command_not_found}}
      {:error, _} = error -> error
    end
  end

  defp prepare_image_resize_args(
         %{max_width: max_width, max_height: max_height, format: "png"} = options
       ) do
    quality = options[:quality] || 85
    resize = Enum.join([max_width, "x", max_height, ">"])

    args = [
      "-resize",
      resize,
      "-quality",
      to_string(quality),
      "png:-"
    ]

    {:ok, args}
  end

  defp prepare_image_resize_args(%{max_width: max_width, max_height: max_height} = options) do
    quality = options[:quality] || 85
    resize = Enum.join([max_width, "x", max_height, ">"])

    args = [
      "-interlace",
      "Plane",
      "-resize",
      resize,
      "-quality",
      to_string(quality),
      "jpg:-"
    ]

    {:ok, args}
  end

  defp prepare_image_resize_args(_), do: {:error, :missing_options}

  def video_framegrab(url) do
    with executable when is_binary(executable) <- System.find_executable("ffmpeg"),
         {:ok, fifo_path} <- mkfifo(),
         args = [
           "-y",
           "-i",
           fifo_path,
           "-vframes",
           "1",
           "-f",
           "mjpeg",
           "-loglevel",
           "error",
           "-"
         ] do
      stream_through_fifo(url, fifo_path, executable, args)
    else
      nil -> {:error, {:ffmpeg, :command_not_found}}
      {:error, _} = error -> error
    end
  end

  defp stream_loop(http_client, fifo, ffmpeg_pid) do
    case ReverseProxy.Client.stream_body(http_client) do
      :done ->
        # Edge case (ffmpeg has not started processing partial input)
        close_http_client(http_client)
        loop_recv(ffmpeg_pid)

      {:ok, data, http_client} ->
        # Will be true if port is alive, not busy, and has received the input
        command_sent =
          try do
            Port.command(fifo, data, [:nosuspend])
          rescue
            _ -> false
          end

        if command_sent do
          stream_loop(http_client, fifo, ffmpeg_pid)
        else
          close_http_client(http_client)
          loop_recv(ffmpeg_pid)
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp close_http_client(http_client) do
    ReverseProxy.Client.close(http_client)
  end

  defp stream_through_fifo(url, fifo_path, executable, args) do
    ffmpeg_pid =
      Port.open({:spawn_executable, executable}, [
        :use_stdio,
        :stream,
        :exit_status,
        :binary,
        args: args
      ])

    fifo = Port.open(to_charlist(fifo_path), [:eof, :binary, :stream, :out])
    Process.unlink(fifo)

    with {:ok, code, _headers, client} when code in 200..299 <-
           ReverseProxy.Client.request(:get, url, [], "", pool: :media) do
      stream_loop(client, fifo, ffmpeg_pid)
    end
  after
    File.rm(fifo_path)
  end

  defp run_fifo(fifo_path, env, executable, args) do
    pid =
      Port.open({:spawn_executable, executable}, [
        :use_stdio,
        :stream,
        :exit_status,
        :binary,
        args: args
      ])

    fifo = Port.open(to_charlist(fifo_path), [:eof, :binary, :stream, :out])

    fix = Pleroma.Helpers.QtFastStart.fix(env.body)
    true = Port.command(fifo, fix)
    :erlang.port_close(fifo)
    loop_recv(pid)
  after
    File.rm(fifo_path)
  end

  defp mkfifo do
    path = "#{@tmp_base}#{to_charlist(:erlang.phash2(self()))}"

    case System.cmd("mkfifo", [path]) do
      {_, 0} ->
        spawn(fifo_guard(path))
        {:ok, path}

      {_, err} ->
        {:error, {:fifo_failed, err}}
    end
  end

  defp fifo_guard(path) do
    pid = self()

    fn ->
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} ->
          File.rm(path)
      end
    end
  end

  defp loop_recv(pid) do
    loop_recv(pid, <<>>)
  end

  defp loop_recv(pid, acc) do
    receive do
      {^pid, {:data, data}} ->
        loop_recv(pid, acc <> data)

      {^pid, {:exit_status, 0}} ->
        {:ok, acc}

      {^pid, {:exit_status, status}} ->
        {:error, status}
    after
      5000 ->
        :erlang.port_close(pid)
        {:error, :timeout}
    end
  end
end
