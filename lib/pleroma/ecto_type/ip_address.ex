# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.EctoType.IpAddress do
  alias Postgrex.INET
  @behaviour Ecto.Type

  def type, do: :inet

  def cast(%INET{address: ip, netmask: nil}), do: {:ok, ip}
  def cast(ip) when is_tuple(ip), do: {:ok, ip}

  def load(%INET{address: ip, netmask: nil}), do: {:ok, ip}

  def dump(ip) when is_tuple(ip), do: {:ok, %INET{address: ip, netmask: nil}}
  def dump(_), do: :error

  def equal?(a, b), do: a == b

  def embed_as(_), do: :self
end
