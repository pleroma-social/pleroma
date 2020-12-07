# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.ClosePollValidator do
  use Ecto.Schema

  alias Pleroma.EctoType.ActivityPub.ObjectValidators

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field(:id, ObjectValidators.ObjectID, primary_key: true)
    field(:type, :string)
    field(:object, ObjectValidators.ObjectID)
  end

  def cast_and_validate(data) do
    data
    |> cast_data()
    |> validate_data()
  end

  def cast_data(data) do
    %__MODULE__{}
    |> changeset(data)
  end

  def changeset(struct, data) do
    struct
    |> cast(data, __schema__(:fields))
  end

  def validate_data(data_cng) do
    data_cng
    |> validate_inclusion(:type, ["ClosePoll"])
    |> validate_required([:id, :type, :object])
  end
end