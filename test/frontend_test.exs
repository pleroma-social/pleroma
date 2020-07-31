# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.FrontendTest do
  use ExUnit.Case
  use Pleroma.Tests.Helpers

  describe "get_config/1" do
    test "Primary config" do
      config = %{"name" => "monsta", "ref" => "pika"}

      clear_config([:frontends, :primary], config)

      fe_config = Pleroma.Frontend.get_config()
      assert fe_config["config"] == config
      assert fe_config["controller"] == Pleroma.Web.Frontend.MonstaController
    end

    test "Headless" do
      config = %{"name" => "none", "ref" => "void"}

      clear_config([:frontends, :primary], config)

      fe_config = Pleroma.Frontend.get_config()
      assert fe_config["config"] == %{}
      assert fe_config["controller"] == Pleroma.Web.Frontend.HeadlessController
    end
  end

  describe "file_path/2" do
    @dir "test/tmp/instance_static"
    @filename "gif.bat"

    setup do
      File.mkdir_p!(@dir)

      config = %{"name" => "monsta", "ref" => "mew"}

      clear_config([:frontends, :primary], config)
      clear_config([:instance, :static_dir], @dir)

      fe_path = Path.join([@dir, "frontends", config["name"], config["ref"]])
      File.mkdir_p!(fe_path)
      priv_path = Application.app_dir(:pleroma, ["priv", "static"])

      on_exit(fn ->
        File.rm_rf(@dir)
        File.rm(Path.join(priv_path, @filename))
      end)

      {:ok, %{frontend_path: fe_path, priv_path: priv_path}}
    end

    test "instance static path priority", %{frontend_path: fp, priv_path: pp} do
      Enum.each([@dir, fp, pp], &File.write!(Path.join(&1, @filename), "sup"))

      assert Pleroma.Frontend.file_path(@filename) == {:ok, Path.join(@dir, @filename)}
    end

    test "frontend path priority", %{frontend_path: fp, priv_path: pp} do
      Enum.each([fp, pp], &File.write!(Path.join(&1, @filename), "sup"))

      assert Pleroma.Frontend.file_path(@filename) == {:ok, Path.join(fp, @filename)}
    end

    test "priv path fallback", %{priv_path: pp} do
      File.write!(Path.join(pp, @filename), "sup")

      assert Pleroma.Frontend.file_path(@filename) == {:ok, Path.join(pp, @filename)}
    end

    test "non-existing file" do
      assert {:error, error} = Pleroma.Frontend.file_path("miseeen.jgp.pgn.mp5.avee")

      assert String.valid?(error)
    end
  end
end
