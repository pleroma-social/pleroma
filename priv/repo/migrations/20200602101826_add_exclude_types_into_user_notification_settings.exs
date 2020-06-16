defmodule Pleroma.Repo.Migrations.AddExcludeTypesIntoUserNotificationSettings do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE users SET notification_settings = jsonb_set(notification_settings, '{exclude_types}', '[]') WHERE local = true;
    """)
  end

  def down, do: :ok
end
