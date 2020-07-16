# # Pleroma: A lightweight social networking server
# # Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# # SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.HackneySupervisor do
  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, :no_arg)
  end

  def init(_) do
    pools = [:federation, :media]

    pools =
      if Pleroma.Config.get([Pleroma.Upload, :proxy_remote]) do
        [:upload | pools]
      else
        pools
      end

    children =
      for pool <- pools do
        options = Pleroma.Config.get([:hackney_pools, pool])
        :hackney_pool.child_spec(pool, options)
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
