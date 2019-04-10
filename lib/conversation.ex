# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Conversation do
  alias Pleroma.Repo
  alias Pleroma.Conversation.Participation
  alias Pleroma.User
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversations" do
    # This is the context ap id.
    field(:ap_id, :string)
    has_many(:participations, Participation)

    timestamps()
  end

  def creation_cng(struct, params) do
    struct
    |> cast(params, [:ap_id])
    |> validate_required([:ap_id])
    |> unique_constraint(:ap_id)
  end

  def create_for_ap_id(ap_id) do
    %__MODULE__{}
    |> creation_cng(%{ap_id: ap_id})
    |> Repo.insert(
      on_conflict: [set: [updated_at: NaiveDateTime.utc_now()]],
      returning: true,
      conflict_target: :ap_id
    )
  end

  def get_for_ap_id(ap_id) do
    Repo.get_by(__MODULE__, ap_id: ap_id)
  end

  @doc """
  This will
  1. Create a conversation if there isn't one already
  2. Create a participation for all the people involved who don't have one already
  3. Bump all relevant participations to 'unread'
  """
  def create_or_bump_for(activity) do
    with true <- Pleroma.Web.ActivityPub.Visibility.is_direct?(activity),
         "Create" <- activity.data["type"],
         "Note" <- activity.data["object"]["type"],
         ap_id when is_binary(ap_id) <- activity.data["object"]["context"] do
      {:ok, conversation} = create_for_ap_id(ap_id)

      local_users = User.get_users_from_set(activity.recipients, true)

      participations =
        Enum.map(local_users, fn user ->
          {:ok, participation} =
            Participation.create_for_user_and_conversation(user, conversation)

          participation
        end)

      %{
        conversation
        | participations: participations
      }
    end
  end
end
