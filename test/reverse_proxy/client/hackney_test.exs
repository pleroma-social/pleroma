defmodule Pleroma.ReverseProxy.Client.HackneyTest do
  use Pleroma.ReverseProxyClientCase, client: Pleroma.ReverseProxy.Client.Hackney

  defp check_ref(ref) do
    assert is_reference(ref)
  end
end
