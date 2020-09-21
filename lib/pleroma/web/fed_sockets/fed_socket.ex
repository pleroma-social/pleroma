# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.FedSocket do
  require Logger

  @shake "61dd18f7-f1e6-49a4-939a-a749fcdc1103"

  def shake, do: @shake
end
