# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Captcha.Error do
  import Pleroma.Web.Gettext

  def message(_reason, opts \\ [])

  def message(:missing_field, %{name: name}) do
    dgettext(
      "errors",
      "Invalid CAPTCHA (Missing parameter: %{name})",
      name: name
    )
  end

  def message(:captcha_error, _) do
    dgettext("errors", "CAPTCHA Error")
  end

  def message(:invalid, _) do
    dgettext("errors", "Invalid CAPTCHA")
  end

  def message(:kocaptcha_service_unavailable, _) do
    dgettext("errors", "Kocaptcha service unavailable")
  end

  def message(:expired, _) do
    dgettext("errors", "CAPTCHA expired")
  end

  def message(:already_used, _) do
    dgettext("errors", "CAPTCHA already used")
  end

  def message(:invalid_answer_data, _) do
    dgettext("errors", "Invalid answer data")
  end

  def message(error, _), do: error
end
