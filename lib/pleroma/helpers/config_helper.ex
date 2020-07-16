# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Helpers.ConfigHelper do
  alias Pleroma.Config

  require Logger

  @spec instance_name() :: String.t() | nil
  def instance_name, do: Config.get([:instance, :name])

  @spec sender() :: {String.t() | nil, String.t() | nil}
  def sender do
    {instance_name(), instance_notify_email()}
  end

  defp instance_notify_email do
    Config.get([:instance, :notify_email]) || Config.get([:instance, :email])
  end
end
