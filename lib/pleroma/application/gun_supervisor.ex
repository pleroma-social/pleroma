# Pleroma: A lightweight social networking server
# # Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# # SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.GunSupervisor do
  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, :no_args)
  end

  def init(_) do
    children =
      Pleroma.Gun.ConnectionPool.children() ++
        [{Task, &Pleroma.HTTP.AdapterHelper.Gun.limiter_setup/0}]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
