# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ApiSpec.Admin.TagOperation do
  alias OpenApiSpex.Operation
  alias OpenApiSpex.Schema

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
      parameters: [
        Operation.parameter(
          :nicknames,
          :query,
          %Schema{type: :array, items: %Schema{type: :string}},
          "User's nicknames"
        ),
        Operation.parameter(
          :tags,
          :query,
          %Schema{type: :array, items: %Schema{type: :string}},
          "tags"
        )
      ],
      responses: %{
        200 => empty_object_response()
      },
      security: [%{"oAuth" => ["write:accounts"]}]
    }
  end

  def untag_operation do
    %Operation{
      tags: ["Admin", "Tags"],
      summary: "Remove tags from users.",
      operationId: "AdminAPI.TagController.untag",
      parameters: [
        Operation.parameter(
          :nicknames,
          :query,
          %Schema{type: :array, items: %Schema{type: :string}},
          "User's nicknames"
        ),
        Operation.parameter(
          :tags,
          :query,
          %Schema{type: :array, items: %Schema{type: :string}},
          "tags"
        )
      ],
      responses: %{
        200 => empty_object_response()
      },
      security: [%{"oAuth" => ["write:accounts"]}]
    }
  end
end
