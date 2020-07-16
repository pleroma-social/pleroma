# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Config.Version do
  @moduledoc """
  IMPORTANT!!!
  Before modifying records in the database directly, please read "Config versioning" in `docs/dev.md`.
  """

  use Ecto.Schema

  import Ecto.Query, only: [from: 2]

  schema "config_versions" do
    field(:backup, Pleroma.EctoType.Config.BinaryValue)
    field(:current, :boolean, default: true)

    timestamps()
  end

  def all do
    from(v in __MODULE__, order_by: [desc: v.id]) |> Pleroma.Repo.all()
  end
end
