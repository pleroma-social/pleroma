defmodule Pleroma.Repo.Migrations.ChangeUserEmailNotificationsSetting do
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]

  def up, do: stream_and_update_users(:up)

  def down, do: stream_and_update_users(:down)

  defp stream_and_update_users(direction) do
    from(u in Pleroma.User, select: [:id, :email_notifications])
    |> Pleroma.Repo.stream()
    |> Stream.each(&update_user_email_notifications_settings(&1, direction))
    |> Stream.run()
  end

  defp update_user_email_notifications_settings(user, direction) do
    email_notifications = change_email_notifications(user.email_notifications, direction)

    user
    |> Ecto.Changeset.change(email_notifications: email_notifications)
    |> Pleroma.Repo.update()
  end

  defp change_email_notifications(email_notifications, :up) do
    Map.put(email_notifications, "notifications", ["mention", "pleroma:chat_mention"])
  end

  defp change_email_notifications(email_notifications, :down) do
    Map.delete(email_notifications, "notifications")
  end
end
