# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.TwitterAPI.TwitterAPI do
  alias Pleroma.Emails.Mailer
  alias Pleroma.Emails.UserEmail
  alias Pleroma.User
  alias Pleroma.UserInviteToken

  @spec register_user(map(), keyword()) :: {:ok, User.t()} | {:error, map()}
  def register_user(params, opts \\ []) do
    params =
      params
      |> Map.take([:email, :token, :password])
      |> Map.put(:bio, params |> Map.get(:bio, "") |> User.parse_bio())
      |> Map.put(:nickname, params[:username])
      |> Map.put(:name, Map.get(params, :fullname, params[:username]))
      |> Map.put(:password_confirmation, params[:password])
      |> Map.put(:registration_reason, params[:reason])

    if Pleroma.Config.get([:instance, :registrations_open]) do
      create_user(params, opts)
    else
      create_user_with_invite(params, opts)
    end
  end

  @spec create_user_with_invite(map(), keyword()) :: {:ok, User.t()} | {:error, map()}
  defp create_user_with_invite(params, opts) do
    with %{token: token} when is_binary(token) <- params,
         {:ok, invite} <- UserInviteToken.find_by_token(token),
         true <- UserInviteToken.valid_invite?(invite) do
      UserInviteToken.update_usage!(invite)
      create_user(params, opts)
    else
      nil -> {:error, %{invite: ["Invalid token"]}}
      _ -> {:error, %{invite: ["Expired token"]}}
    end
  end

  @spec create_user(map(), keyword()) :: {:ok, User.t()} | {:error, map()}
  defp create_user(params, opts) do
    changeset = User.register_changeset(%User{}, params, opts)

    case User.register(changeset) do
      {:ok, user} ->
        maybe_notify_admins(user)
        {:ok, user}

      {:error, changeset} ->
        {:error, Pleroma.EctoHelper.pretty_errors(changeset.errors)}
    end
  end

  defp maybe_notify_admins(%User{} = account) do
    if Pleroma.Config.get([:instance, :account_approval_required]) do
      User.all_superusers()
      |> Enum.filter(fn user -> not is_nil(user.email) end)
      |> Enum.each(fn superuser ->
        superuser
        |> Pleroma.Emails.AdminEmail.new_unapproved_registration(account)
        |> Pleroma.Emails.Mailer.deliver_async()
      end)
    end
  end

  def password_reset(nickname_or_email) do
    with true <- is_binary(nickname_or_email),
         %User{local: true, email: email, deactivated: false} = user when is_binary(email) <-
           User.get_by_nickname_or_email(nickname_or_email),
         {:ok, token_record} <- Pleroma.PasswordResetToken.create_token(user) do
      user
      |> UserEmail.password_reset_email(token_record.token)
      |> Mailer.deliver_async()

      {:ok, :enqueued}
    else
      _ ->
        {:ok, :noop}
    end
  end

  def validate_captcha(app, params) do
    if app.trusted || not Pleroma.Captcha.enabled?() do
      :ok
    else
      do_validate_captcha(params)
    end
  end

  defp do_validate_captcha(params) do
    with :ok <- validate_captcha_presence(params),
         :ok <-
           Pleroma.Captcha.validate(
             params[:captcha_token],
             params[:captcha_solution],
             params[:captcha_answer_data]
           ) do
      :ok
    else
      {:error, error} ->
        {:error, %{captcha: [Pleroma.Captcha.Error.message(error)]}}
    end
  end

  defp validate_captcha_presence(params) do
    [:captcha_solution, :captcha_token, :captcha_answer_data]
    |> Enum.find_value(:ok, fn key ->
      unless is_binary(params[key]) do
        {:error, Pleroma.Captcha.Error.message(:missing_field, %{name: key})}
      end
    end)
  end
end
