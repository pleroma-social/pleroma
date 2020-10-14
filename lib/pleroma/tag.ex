# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Tag do
  use Ecto.Schema

  import Ecto.Query

  alias Pleroma.Repo
  alias Pleroma.Web.ActivityPub.MRF

  @type t :: %__MODULE__{}

  schema "tags" do
    field(:name, :string)

    timestamps()
  end

  @spec upsert(String.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def upsert(name) do
    %__MODULE__{}
    |> Ecto.Changeset.change(name: name)
    |> Ecto.Changeset.unique_constraint(:name)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :name)
  end

  @spec list_tags() :: list(String.t())
  def list_tags do
    from(u in __MODULE__, select: u.name)
    |> Repo.all()
    |> Kernel.++(MRF.TagPolicy.policy_tags())
    |> Enum.uniq()
    |> Enum.sort()
  end
end
