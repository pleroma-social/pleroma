# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.AdminAPI.ConfigView do
  use Pleroma.Web, :view

  def render("index.json", %{configs: configs} = params) do
    %{
      configs: render_many(configs, __MODULE__, "show.json", as: :config),
      need_reboot: params[:need_reboot]
    }
  end

  def render("index.json", %{versions: versions}) do
    %{
      versions: render_many(versions, __MODULE__, "show.json", as: :version)
    }
  end

  def render("show.json", %{config: config}) do
    config
    |> Map.take([:group, :key, :value, :db])
    |> Map.new(fn
      {k, v} -> {k, Pleroma.Config.Converter.to_json_types(v)}
    end)
  end

  def render("show.json", %{version: version}) do
    version
    |> Map.take([:id, :current])
    |> Map.put(:inserted_at, Pleroma.Web.CommonAPI.Utils.to_masto_date(version.inserted_at))
  end
end
