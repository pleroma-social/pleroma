defmodule Mix.Tasks.Pleroma.FrontendTest do
  use ExUnit.Case

  import Tesla.Mock

  @path Pleroma.Config.get([:instance, :frontends_dir])

  setup do
    Mix.shell(Mix.Shell.Process)

    mock(fn
      %{
        method: :get,
        url:
          "https://git.pleroma.social/pleroma/pleroma-fe/-/jobs/artifacts/master/download?job=build"
      } ->
        %Tesla.Env{status: 200, body: File.read!("test/instance_static/dist.zip")}

      %{
        method: :get,
        url:
          "https://git.pleroma.social/pleroma/pleroma-fe/-/jobs/artifacts/develop/download?job=build"
      } ->
        %Tesla.Env{status: 200, body: File.read!("test/instance_static/dist.zip")}
    end)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      {:ok, _} = File.rm_rf(@path)
    end)

    :ok
  end

  test "downloads pleroma-fe and master by default" do
    Mix.Tasks.Pleroma.Frontend.run(["download"])

    @path |> Path.expand() |> Path.join("pleroma-fe") |> check_assertions("master")
  end

  test "download special fe with reference" do
    ref = "develop"
    Mix.Tasks.Pleroma.Frontend.run(["download", "-r", ref])

    @path |> Path.expand() |> Path.join("pleroma-fe") |> check_assertions(ref)
  end

  defp check_assertions(path, ref) do
    assert_receive {:mix_shell, :info, [message]}
    assert message == "Downloading reference #{ref}"
    assert_receive {:mix_shell, :info, [message]}
    assert message == "Cleaning #{path}"
    assert_receive {:mix_shell, :info, [message]}
    assert message == "Writing to #{path}"
    assert_receive {:mix_shell, :info, ["Successfully downloaded and unpacked the frontend"]}
    assert File.exists?(path <> "/1.png")
    assert File.exists?(path <> "/2.css")
    assert File.exists?(path <> "/3.js")
  end
end
