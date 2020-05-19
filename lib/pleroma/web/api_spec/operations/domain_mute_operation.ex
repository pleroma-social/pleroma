# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ApiSpec.DomainMuteOperation do
  alias OpenApiSpex.Operation
  alias OpenApiSpex.Schema
  import Pleroma.Web.ApiSpec.Helpers

  def open_api_operation(action) do
    operation = String.to_existing_atom("#{action}_operation")
    apply(__MODULE__, operation, [])
  end

  def index_operation do
    %Operation{
      tags: ["domain_mutes"],
      summary: "Fetch domain mutes",
      description: "View domains the user has muted.",
      security: [%{"oAuth" => ["follow", "read:mutes"]}],
      operationId: "DomainMuteController.index",
      responses: %{
        200 =>
          Operation.response("Domain mutes", "application/json", %Schema{
            description: "Response schema for domain mutes",
            type: :array,
            items: %Schema{type: :string},
            example: ["google.com", "facebook.com"]
          })
      }
    }
  end

  def create_operation do
    %Operation{
      tags: ["domain_mutes"],
      summary: "Mute a domain",
      description: """
      Mute a domain to:

      - hide all posts from it
      - hide all notifications from it
      """,
      operationId: "DomainMuteController.create",
      requestBody: domain_mute_request(),
      security: [%{"oAuth" => ["follow", "write:mutes"]}],
      responses: %{200 => empty_object_response()}
    }
  end

  def delete_operation do
    %Operation{
      tags: ["domain_mutes"],
      summary: "Unmute a domain",
      description: "Remove a domain mute, if it exists in the user's array of muted domains.",
      operationId: "DomainMuteController.delete",
      requestBody: domain_mute_request(),
      security: [%{"oAuth" => ["follow", "write:mutes"]}],
      responses: %{200 => empty_object_response()}
    }
  end

  defp domain_mute_request do
    request_body(
      "Parameters",
      %Schema{
        type: :object,
        properties: %{
          domain: %Schema{type: :string}
        },
        required: [:domain]
      },
      required: true,
      example: %{
        "domain" => "facebook.com"
      }
    )
  end
end
