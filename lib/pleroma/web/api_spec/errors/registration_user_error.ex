# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ApiSpec.Errors.RegistrationUserError do
  @behaviour Plug

  import Plug.Conn, only: [put_status: 2]
  import Phoenix.Controller, only: [json: 2]
  alias Pleroma.Web.ApiSpec.RenderError

  @impl Plug
  def init(opts), do: opts

  @impl Plug

  def call(conn, errors) do
    field_errors =
      errors
      |> Enum.group_by(& &1.name)
      |> Enum.into(%{}, fn {field, field_errors} ->
        {field, Enum.map(field_errors, &RenderError.message/1)}
      end)

    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "Please review the submission",
      identifier: "review_submission",
      fields: field_errors
    })
  end
end
