defmodule Pleroma.Repo.Migrations.FillNotificationsNotifiedAt do
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]

  @types ["mention", "pleroma:chat_mention"]

  def up do
    from(n in "notifications",
      where: is_nil(n.notified_at),
      where: n.type in ^@types
    )
    |> Pleroma.Repo.update_all(set: [notified_at: NaiveDateTime.utc_now()])
  end

  def down do
    from(n in "notifications",
      where: not is_nil(n.notified_at),
      where: n.type in ^@types
    )
    |> Pleroma.Repo.update_all(set: [notified_at: nil])
  end
end
