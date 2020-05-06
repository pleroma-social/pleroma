# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.AttachmentValidator do
  use Ecto.Schema

  alias Pleroma.Web.ActivityPub.ObjectValidators
  alias Pleroma.Web.ActivityPub.ObjectValidators.Types

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    embeds_one(:url, ObjectValidators.AttachmentURLValidator)
    field(:mediaType, :string)
    field(:type, :string)
    field(:name, :string)
  end

  def cast_and_validate(data) do
    data
    |> cast_data()
    |> validate_data()
  end

  def cast_data(data) do
    %__MODULE__{}
    |> cast(data, __schema__(:fields))
  end

  def validate_data(data_cng) do
    data_cng
    |> validate_inclusion(:type, ["Audio", "Video", "Image", "Document", "Link"])
    |> validate_format(:mediaType, ~r[.+/.+])
    |> validate_required([:url])
  end
end

defmodule Pleroma.Web.ActivityPub.ObjectValidators.AttachmentURLValidator do
  use Ecto.Schema

  alias Pleroma.Web.ActivityPub.ObjectValidators.Types

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field(:href, Types.Uri)
    field(:mediaType, :string)
    field(:type, :string)
  end

  def cast_and_validate(data) do
    data
    |> cast_data()
    |> validate_data()
  end

  def cast_data(data) do
    %__MODULE__{}
    |> cast(data, __schema__(:fields))
  end

  def validate_data(data_cng) do
    data_cng
    |> validate_inclusion(:type, ["Audio", "Video", "Image", "Link"])
    |> validate_format(:mediaType, ~r[.+/.+])
    |> validate_required([:href])
  end
end
