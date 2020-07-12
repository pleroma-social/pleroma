defmodule Pleroma.Repo.Migrations.AddAttachmentFilenameSettingToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:show_attachment_filenames, :boolean, default: false)
    end
  end
end
