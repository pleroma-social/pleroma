defmodule Pleroma.Repo.Migrations.FillRecipientUsersInActivities do
  use Ecto.Migration

  alias Pleroma.RepoStreamer
  alias Pleroma.User

  import Ecto.Query

  def up do
    # copy users without as:Public
    execute("""
    update activities set recipient_users = array_remove(recipients, 'https://www.w3.org/ns/activitystreams#Public');
    """)

    # strip followers collections
    from(
      u in User,
      where: not(is_nil(u.follower_address))
    )
    |> RepoStreamer.chunk_stream(512)
    |> Stream.each(fn chunk ->
      chunk
      |> Enum.each(fn %User{} = u ->
        execute("update activities set recipient_users = array_remove(recipient_users, '#{u.follower_address}') where recipient_users && array['#{u.follower_address}'::varchar]")
      end)
    end)
    |> Stream.run()
  end

  def down, do: :ok
end
