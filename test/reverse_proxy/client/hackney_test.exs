# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.ReverseProxy.Client.HackneyTest do
  use Pleroma.ReverseProxyClientCase, client: Pleroma.ReverseProxy.Client.Hackney

  defp check_ref(ref) do
    assert is_reference(ref)
  end
end
