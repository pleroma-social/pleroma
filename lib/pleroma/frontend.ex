# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Frontend do
  @type primary_fe_opts :: %{config: Map.t(), controller: Module.t(), static: boolean()}

  @spec get_primary_fe_opts() :: primary_fe_opts()
  def get_primary_fe_opts,
    do: [:frontends] |> Pleroma.Config.get(%{}) |> Enum.into(%{}) |> get_primary_fe_opts()

  @spec get_primary_fe_opts(Map.t()) :: primary_fe_opts()
  def get_primary_fe_opts(%{primary: %{"name" => "none"}} = fe_config) do
    %{
      config: %{},
      controller: Pleroma.Web.Frontend.HeadlessController,
      static: fe_config[:static] || false
    }
  end

  def get_primary_fe_opts(fe_config) do
    %{
      config: fe_config[:primary],
      controller:
        Module.concat([
          Pleroma.Web.Frontend,
          String.capitalize(fe_config[:primary]["name"]) <> "Controller"
        ]),
      static: fe_config[:static] || false
    }
  end
end
