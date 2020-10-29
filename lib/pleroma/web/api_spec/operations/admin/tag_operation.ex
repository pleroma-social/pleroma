# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ApiSpec.Admin.TagOperation do
  alias OpenApiSpex.Operation
  alias OpenApiSpex.Schema
  alias Pleroma.Web.ApiSpec.Schemas.ApiError

  import Pleroma.Web.ApiSpec.Helpers

  def open_api_operation(action) do
    operation = String.to_existing_atom("#{action}_operation")
    apply(__MODULE__, operation, [])
  end

  def list_operation do
    %Operation{
      tags: ["Admin", "Tags"],
      summary: "List available tags.",
      operationId: "AdminAPI.TagController.list",
      parameters: admin_api_params(),
      responses: %{
        200 =>
          Operation.response("Array of tags", "application/json", %Schema{
            type: :array,
            items: %Schema{type: :string}
          })
      },
      security: [%{"oAuth" => ["read:accounts"]}]
    }
  end

  def tag_operation do
    %Operation{
      tags: ["Admin", "Tags"],
      summary: "Adds tags to users.",
      operationId: "AdminAPI.TagController.tag",
      parameters: admin_api_params(),
      requestBody:
        request_body(
          "Parameters",
          %Schema{
            type: :object,
            properties: %{
              nicknames: %Schema{type: :array, items: %Schema{type: :string}},
              tags: %Schema{type: :array, items: %Schema{type: :string}}
            }
          },
          required: true
        ),
      responses: %{
        204 => no_content_response(),
        400 => Operation.response("Bad request", "application/json", ApiError)
      },
      security: [%{"oAuth" => ["write:accounts"]}]
    }
  end

  def untag_operation do
    %Operation{
      tags: ["Admin", "Tags"],
      summary: "Remove tags from users.",
      operationId: "AdminAPI.TagController.untag",
      parameters: admin_api_params(),
      requestBody:
        request_body(
          "Parameters",
          %Schema{
            type: :object,
            properties: %{
              nicknames: %Schema{type: :array, items: %Schema{type: :string}},
              tags: %Schema{type: :array, items: %Schema{type: :string}}
            }
          },
          required: true
        ),
      responses: %{
        204 => no_content_response(),
        400 => Operation.response("Bad request", "application/json", ApiError)
      },
      security: [%{"oAuth" => ["write:accounts"]}]
    }
  end
end
