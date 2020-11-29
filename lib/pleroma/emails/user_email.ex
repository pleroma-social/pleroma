# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Emails.UserEmail do
  @moduledoc "User emails"

  use Phoenix.Swoosh, view: Pleroma.Web.EmailView, layout: {Pleroma.Web.LayoutView, :email}

  alias Pleroma.Config
  alias Pleroma.Notification
  alias Pleroma.User
  alias Pleroma.Web.Endpoint
  alias Pleroma.Web.Router

  import Pleroma.Config.Helpers, only: [instance_name: 0, sender: 0]

  defp recipient(email, nil), do: email
  defp recipient(email, name), do: {name, email}
  defp recipient(%User{} = user), do: recipient(user.email, user.name)

  @spec welcome(User.t(), map()) :: Swoosh.Email.t()
  def welcome(user, opts \\ %{}) do
    new()
    |> to(recipient(user))
    |> from(Map.get(opts, :sender, sender()))
    |> subject(Map.get(opts, :subject, "Welcome to #{instance_name()}!"))
    |> html_body(Map.get(opts, :html, "Welcome to #{instance_name()}!"))
    |> text_body(Map.get(opts, :text, "Welcome to #{instance_name()}!"))
  end

  def password_reset_email(user, token) when is_binary(token) do
    password_reset_url = Router.Helpers.reset_password_url(Endpoint, :reset, token)

    html_body = """
    <h3>Reset your password at #{instance_name()}</h3>
    <p>Someone has requested password change for your account at #{instance_name()}.</p>
    <p>If it was you, visit the following link to proceed: <a href="#{password_reset_url}">reset password</a>.</p>
    <p>If it was someone else, nothing to worry about: your data is secure and your password has not been changed.</p>
    """

    new()
    |> to(recipient(user))
    |> from(sender())
    |> subject("Password reset")
    |> html_body(html_body)
  end

  def user_invitation_email(
        user,
        %Pleroma.UserInviteToken{} = user_invite_token,
        to_email,
        to_name \\ nil
      ) do
    registration_url =
      Router.Helpers.redirect_url(
        Endpoint,
        :registration_page,
        user_invite_token.token
      )

    html_body = """
    <h3>You are invited to #{instance_name()}</h3>
    <p>#{user.name} invites you to join #{instance_name()}, an instance of Pleroma federated social networking platform.</p>
    <p>Click the following link to register: <a href="#{registration_url}">accept invitation</a>.</p>
    """

    new()
    |> to(recipient(to_email, to_name))
    |> from(sender())
    |> subject("Invitation to #{instance_name()}")
    |> html_body(html_body)
  end

  def account_confirmation_email(user) do
    confirmation_url =
      Router.Helpers.confirm_email_url(
        Endpoint,
        :confirm_email,
        user.id,
        to_string(user.confirmation_token)
      )

    html_body = """
    <h3>Welcome to #{instance_name()}!</h3>
    <p>Email confirmation is required to activate the account.</p>
    <p>Click the following link to proceed: <a href="#{confirmation_url}">activate your account</a>.</p>
    """

    new()
    |> to(recipient(user))
    |> from(sender())
    |> subject("#{instance_name()} account confirmation")
    |> html_body(html_body)
  end

  def approval_pending_email(user) do
    html_body = """
    <h3>Awaiting Approval</h3>
    <p>Your account at #{instance_name()} is being reviewed by staff. You will receive another email once your account is approved.</p>
    """

    new()
    |> to(recipient(user))
    |> from(sender())
    |> subject("Your account is awaiting approval")
    |> html_body(html_body)
  end

  defp prepare_mention(%Notification{type: type} = notification, acc)
       when type in ["mention", "pleroma:chat_mention"] do
    object = Pleroma.Object.normalize(notification.activity, fetch: false)

    if object do
      object = update_in(object.data["content"], &format_links/1)

      mention = %{
        data: notification,
        object: object,
        from: User.get_by_ap_id(notification.activity.actor)
      }

      [mention | acc]
    else
      acc
    end
  end

  defp prepare_mention(_, acc), do: acc

  @doc """
  Email used in digest email notifications
  Includes Mentions and New Followers data
  If there are no mentions (even when new followers exist), the function will return nil
  """
  @spec digest_email(User.t()) :: Swoosh.Email.t() | nil
  def digest_email(user) do
    notifications = Notification.for_user_since(user, user.last_digest_emailed_at)

    mentions =
      notifications
      |> Enum.filter(&(&1.activity.data["type"] == "Create"))
      |> Enum.reduce([], &prepare_mention/2)

    followers =
      notifications
      |> Enum.filter(&(&1.activity.data["type"] == "Follow"))
      |> Enum.map(fn notification ->
        from = User.get_by_ap_id(notification.activity.actor)

        if not is_nil(from) do
          %{
            data: notification,
            object: Pleroma.Object.normalize(notification.activity, fetch: false),
            from: User.get_by_ap_id(notification.activity.actor)
          }
        end
      end)
      |> Enum.filter(& &1)

    unless Enum.empty?(mentions) do
      styling = Config.get([__MODULE__, :styling])

      html_data = %{
        instance: instance_name(),
        user: user,
        mentions: mentions,
        followers: followers,
        unsubscribe_link: unsubscribe_url(user, "digest"),
        styling: styling
      }

      {logo_path, logo} = logo_path()

      new()
      |> to(recipient(user))
      |> from(sender())
      |> subject("Your digest from #{instance_name()}")
      |> put_layout(false)
      |> render_body("digest.html", Map.put(html_data, :logo, logo))
      |> attachment(Swoosh.Attachment.new(logo_path, filename: logo, type: :inline))
    end
  end

  defp format_links(str) do
    re = ~r/<a.+href=['"].*>/iU
    %{link_color: color} = Config.get([__MODULE__, :styling])

    Regex.replace(re, str, fn link ->
      String.replace(link, "<a", "<a style=\"color: #{color};text-decoration: none;\"")
    end)
  end

  @doc """
  Generate unsubscribe link for given user and notifications type.
  The link contains JWT token with the data, and subscription can be modified without
  authorization.
  """
  @spec unsubscribe_url(User.t(), String.t()) :: String.t()
  def unsubscribe_url(user, notifications_type) do
    token =
      %{"sub" => user.id, "act" => %{"unsubscribe" => notifications_type}, "exp" => false}
      |> Pleroma.JWT.generate_and_sign!()
      |> Base.encode64()

    Router.Helpers.subscription_url(Endpoint, :unsubscribe, token)
  end

  def backup_is_ready_email(backup, admin_user_id \\ nil) do
    %{user: user} = Pleroma.Repo.preload(backup, :user)
    download_url = Pleroma.Web.PleromaAPI.BackupView.download_url(backup)

    html_body =
      if is_nil(admin_user_id) do
        """
        <p>You requested a full backup of your Pleroma account. It's ready for download:</p>
        <p><a href="#{download_url}">#{download_url}</a></p>
        """
      else
        admin = Pleroma.Repo.get(User, admin_user_id)

        """
        <p>Admin @#{admin.nickname} requested a full backup of your Pleroma account. It's ready for download:</p>
        <p><a href="#{download_url}">#{download_url}</a></p>
        """
      end

    new()
    |> to(recipient(user))
    |> from(sender())
    |> subject("Your account archive is ready")
    |> html_body(html_body)
  end

  @spec mentions_notification_email(User.t(), [Notification.t()]) :: Swoosh.Email.t()
  def mentions_notification_email(user, mentions) do
    html_data = %{
      instance: instance_name(),
      user: user,
      mentions: Enum.reduce(mentions, [], &prepare_mention/2),
      unsubscribe_link: unsubscribe_url(user, "mentions_email"),
      styling: Config.get([__MODULE__, :styling])
    }

    now = NaiveDateTime.utc_now()

    {logo_path, logo} = logo_path()

    new()
    |> to(recipient(user))
    |> from(sender())
    |> subject(
      "[Pleroma] New mentions from #{instance_name()} for #{
        Timex.format!(now, "{Mfull} {D}, {YYYY} at {h12}:{m} {AM}")
      }"
    )
    |> put_layout(false)
    |> render_body("mentions.html", Map.put(html_data, :logo, logo))
    |> attachment(Swoosh.Attachment.new(logo_path, filename: logo, type: :inline))
  end

  defp logo_path do
    logo_path =
      if logo = Config.get([__MODULE__, :logo]) do
        Path.join(Config.get([:instance, :static_dir]), logo)
      else
        Path.join(:code.priv_dir(:pleroma), "static/static/logo.svg")
      end

    {logo_path, Path.basename(logo_path)}
  end
end
