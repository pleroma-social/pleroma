# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.ReverseProxy.Client.TeslaTest do
  use Pleroma.ReverseProxyClientCase, client: Pleroma.ReverseProxy.Client.Tesla

  setup_all do
    Pleroma.Config.put([Pleroma.Gun.API], Pleroma.Gun.API.Gun)

    on_exit(fn ->
      Pleroma.Config.put([Pleroma.Gun.API], Pleroma.Gun.API.Mock)
    end)
  end

  defp check_ref(%{pid: pid, stream: stream} = ref) do
    assert is_pid(pid)
    assert is_reference(stream)
    assert ref[:fin]
  end

  defp close(%{pid: pid}) do
    Pleroma.ReverseProxy.Client.Tesla.close(pid)
  end
end
