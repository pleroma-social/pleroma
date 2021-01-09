# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Tag do
  use Ecto.Schema

  import Ecto.Query

  alias Pleroma.Repo

  @mrf_tags [
    "mrf_tag:media-force-nsfw",
    "mrf_tag:media-strip",
    "mrf_tag:force-unlisted",
    "mrf_tag:sandbox",
    "mrf_tag:disable-remote-subscription",
    "mrf_tag:disable-any-subscription"
  ]

  @type t :: %__MODULE__{}

  schema "tags" do
    field(:name, :string)
    many_to_many(:users, Pleroma.User, join_through: "users_tags", on_replace: :delete)

    timestamps()
  end

  @spec upsert(String.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def upsert(name) do
    %__MODULE__{}
    |> Ecto.Changeset.change(name: normalize_tag(name))
    |> Ecto.Changeset.unique_constraint(:name)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :name)
  end

  @spec upsert_tags(list(String.t())) :: {integer(), nil | [term()]}
  def upsert_tags(names) do
    date = NaiveDateTime.utc_now()

    tags =
      names
      |> normalize_tags()
      |> Enum.map(&%{name: &1, inserted_at: date, updated_at: date})

    Repo.insert_all("tags", tags, on_conflict: :nothing, conflict_target: :name)
  end

  @spec list_tags() :: list(String.t())
  def list_tags do
    from(u in __MODULE__, select: u.name)
    |> Repo.all()
    |> Kernel.++(@mrf_tags)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec get_tag_ids([String.t()]) :: [pos_integer()]
  def get_tag_ids(tag_names) do
    names = normalize_tags(tag_names)

    from(
      u in __MODULE__,
      select: u.id,
      where: u.name in ^names
    )
    |> Repo.all()
  end

  @spec normalize_tags([String.t()]) :: [String.t()]
  def normalize_tags(tag_names) do
    tag_names
    |> List.wrap()
    |> Enum.map(&normalize_tag/1)
  end

  defp normalize_tag(tag_name) do
    tag_name
    |> String.downcase()
    |> String.trim()
  end
end
