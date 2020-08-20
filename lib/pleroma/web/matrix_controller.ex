# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MatrixController do
  use Pleroma.Web, :controller

  alias Pleroma.User
  # alias Pleroma.Web.MediaProxy
  alias Pleroma.Plugs.AuthenticationPlug
  alias Pleroma.Plugs.OAuthScopesPlug
  alias Pleroma.Web.OAuth.App
  alias Pleroma.Web.OAuth.Token
  alias Pleroma.Chat
  alias Pleroma.Chat.MessageReference
  alias Pleroma.Repo
  alias Pleroma.HTML
  import Ecto.Query

  plug(
    OAuthScopesPlug,
    %{scopes: ["write"]}
    when action in [:set_presence_status, :set_filter]
  )

  plug(
    OAuthScopesPlug,
    %{scopes: ["read"]}
    when action in [:pushrules, :sync, :filter, :key_query, :profile]
  )

  def client_versions(conn, _) do
    data = %{
      versions: ["r0.0.1", "r0.1.0", "r0.2.0", "r0.3.0", "r0.4.0", "r0.5.0"]
      # versions: ["r0.0.1", "r0.1.0"]
    }

    conn
    |> json(data)
  end

  def login_info(conn, _) do
    data = %{
      flows: [
        %{type: "m.login.password"}
      ]
    }

    conn
    |> json(data)
  end

  def login(conn, params) do
    username = params["identifier"]["user"]
    password = params["password"]

    dn = params["initial_device_display_name"]

    with %User{} = user <- User.get_by_nickname(username),
         true <- AuthenticationPlug.checkpw(password, user.password_hash),
         {:ok, app} <-
           App.create(%{client_name: dn, scopes: ~w(read write), redirect_uris: "nowhere"}),
         {:ok, token} <- Token.create_token(app, user) do
      data = %{
        user_id: "@#{user.nickname}:#{Pleroma.Web.Endpoint.host()}",
        access_token: token.token,
        device_id: app.client_id
      }

      conn
      |> put_status(200)
      |> json(data)
    else
      _ ->
        data = %{
          errcode: "M_FORBIDDEN",
          error: "Invalid password"
        }

        conn
        |> put_status(403)
        |> json(data)
    end
  end

  def presence_status(conn, _) do
    data = %{
      presence: "online"
    }

    conn
    |> json(data)
  end

  def set_presence_status(conn, params) do
    IO.inspect(params)

    conn
    |> json(%{})
  end

  def pushrules(conn, _) do
    data = %{
      global: %{}
    }

    conn
    |> json(data)
  end

  def set_filter(conn, params) do
    IO.inspect(params)

    filter_id = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    Cachex.put(:matrix_compat, "filter:#{filter_id}", params)

    data = %{
      filter_id: filter_id
    }

    conn
    |> json(data)
  end

  def filter(conn, params) do
    result = Cachex.get(:matrix_compat, "filter:#{params["filter_id"]}")
    IO.inspect(result)

    conn
    |> put_status(200)
    |> json(result)
  end

  defp matrix_name(%{local: true, nickname: nick}) do
    "@#{nick}:#{Pleroma.Web.Endpoint.host()}"
  end

  defp matrix_name(%{nickname: nick}) do
    nick =
      nick
      |> String.replace("@", ":")

    "@" <> nick
  end

  def sync(%{assigns: %{user: user}} = conn, params) do
    with {:ok, timeout} <- Ecto.Type.cast(:integer, params["timeout"]) do
      :timer.sleep(timeout)
    end

    blocked_ap_ids = User.blocked_users_ap_ids(user)

    user_id = user.id

    chats =
      from(c in Chat,
        where: c.user_id == ^user_id,
        where: c.recipient not in ^blocked_ap_ids,
        order_by: [desc: c.updated_at]
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn chat, acc ->
        recipient = User.get_by_ap_id(chat.recipient)

        messages =
          chat
          |> MessageReference.for_chat_query()
          |> Repo.all()
          |> Enum.map(fn message ->
            chat_data = message.object.data
            author = User.get_cached_by_ap_id(chat_data["actor"])

            {:ok, date, _} = DateTime.from_iso8601(chat_data["published"])

            %{
              content: %{
                body: chat_data["content"] |> HTML.strip_tags(),
                msgtype: "m.text",
                format: "org.matrix.custom.html",
                formatted_body: chat_data["content"]
              },
              type: "m.room.message",
              event_id: message.id,
              room_id: chat.id,
              sender: matrix_name(author),
              origin_ts: date |> DateTime.to_unix(),
              unsigned: %{
                age: 0
              }
            }
          end)

        room = %{
          chat.id => %{
            summary: %{
              "m.heroes" => [matrix_name(recipient)],
              "m.joined_member_count" => 2,
              "m.invited_member_count" => 0
            },
            state: %{events: []},
            ephemeral: %{events: []},
            timeline: %{
              events: messages,
              limited: false,
              prev_batch: "prev"
            },
            account_data: %{events: []},
            unread_notifications: %{
              highlight_count: 0,
              notification_count: 0
            }
          }
        }

        Map.merge(acc, room)
      end)

    data = %{
      next_batch: "next",
      rooms: %{
        join: chats,
        invite: %{},
        leave: %{}
      },
      account_data: %{
        events: []
      },
      presence: %{
        events: []
      },
      to_device: %{
        events: []
      },
      device_one_time_keys_count: %{},
      device_lists: %{
        left: [],
        changed: []
      }
    }

    conn
    |> json(data)
  end

  def key_query(conn, params) do
    IO.inspect(params)

    conn
    |> json(params)
  end

  def profile(conn, params) do
    IO.inspect(params)

    nickname =
      params["user_id"]
      |> String.trim_leading("@")
      |> String.replace(":", "@")
      |> String.trim_trailing("@#{Pleroma.Web.Endpoint.host()}")

    user = User.get_by_nickname(nickname)

    data = %{
      displayname: user.name
    }

    conn
    |> json(data)
  end
end
