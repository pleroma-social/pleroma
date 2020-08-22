# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MatrixController do
  use Pleroma.Web, :controller

  # alias Pleroma.Web.MediaProxy
  alias Pleroma.Chat
  alias Pleroma.Chat.MessageReference
  alias Pleroma.HTML
  alias Pleroma.Plugs.AuthenticationPlug
  alias Pleroma.Plugs.OAuthScopesPlug
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.MediaProxy
  alias Pleroma.Web.OAuth.App
  alias Pleroma.Web.OAuth.Token
  alias Pleroma.Web.OAuth.Token
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Object
  import Ecto.Query

  plug(
    OAuthScopesPlug,
    %{scopes: ["write"]}
    when action in [
           :set_presence_status,
           :set_filter,
           :send_event,
           :set_read_marker,
           :typing,
           :set_account_data
         ]
  )

  plug(
    OAuthScopesPlug,
    %{scopes: ["read"]}
    when action in [
           :pushrules,
           :sync,
           :filter,
           :key_query,
           :profile,
           :joined_groups,
           :room_keys_version,
           :key_upload,
           :capabilities,
           :room_members,
           :publicised_groups,
           :turn_server
         ]
  )

  def mxc(url) do
    "mxc://localhost/#{url |> Base.encode64()}"
  end

  def client_versions(conn, _) do
    data = %{
      versions: ["r0.0.1", "r0.1.0", "r0.2.0", "r0.3.0", "r0.4.0", "r0.5.0"]
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

  def set_presence_status(conn, _params) do
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
    filter_id = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    Cachex.put(:matrix_cache, "filter:#{filter_id}", params)

    data = %{
      filter_id: filter_id
    }

    conn
    |> json(data)
  end

  def filter(conn, params) do
    {:ok, result} = Cachex.get(:matrix_cache, "filter:#{params["filter_id"]}")

    conn
    |> put_status(200)
    |> json(result || %{})
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
    with {:ok, timeout} when not is_nil(timeout) <- Ecto.Type.cast(:integer, params["timeout"]) do
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

        membership_events =
          [user, recipient]
          |> membership_events_from_list(chat)

        q =
          chat
          |> MessageReference.for_chat_query()

        q =
          if since = params["since"] do
            from(mr in q,
              where: mr.id > ^since
            )
          else
            q
          end

        messages =
          q
          |> Repo.all()
          |> Enum.map(fn message ->
            chat_data = message.object.data
            author = User.get_cached_by_ap_id(chat_data["actor"])

            {:ok, date, _} = DateTime.from_iso8601(chat_data["published"])
            {:ok, txn_id} = Cachex.get(:matrix_cache, "txn_id:#{message.id}")

            messages = [
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
                origin_server_ts: date |> DateTime.to_unix(:millisecond),
                unsigned: %{
                  age: DateTime.diff(DateTime.utc_now(), date, :millisecond),
                  transaction_id: txn_id
                }
              }
            ]

            messages =
              if attachment = chat_data["attachment"] do
                attachment =
                  Pleroma.Web.MastodonAPI.StatusView.render("attachment.json",
                    attachment: attachment
                  )

                att = %{
                  content: %{
                    body: "an image",
                    msgtype: "m.image",
                    url: mxc(attachment.url),
                    info: %{
                      h: 640,
                      w: 480,
                      size: 500_000,
                      mimetype: attachment.pleroma.mime_type
                    }
                  },
                  type: "m.room.message",
                  event_id: attachment.id,
                  room_id: chat.id,
                  sender: matrix_name(author),
                  origin_server_ts: date |> DateTime.to_unix(:millisecond),
                  unsigned: %{
                    age: DateTime.diff(DateTime.utc_now(), date, :millisecond)
                  }
                }

                [att | messages]
              else
                messages
              end

            messages
          end)
          |> List.flatten()
          |> Enum.reverse()

        room = %{
          chat.id => %{
            summary: %{
              "m.heroes" => [matrix_name(recipient)],
              "m.joined_member_count" => 2,
              "m.invited_member_count" => 0
            },
            state: %{events: membership_events},
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

        if length(messages) > 0 do
          Map.merge(acc, room)
        else
          acc
        end
      end)

    most_recent_cmr_id =
      Enum.reduce(chats, nil, fn {_k, chat}, acc ->
        id = List.last(chat.timeline.events).event_id

        if !acc || (acc && acc < id) do
          id
        else
          acc
        end
      end)

    data = %{
      next_batch: most_recent_cmr_id,
      rooms: %{
        join: chats,
        invite: %{},
        leave: %{}
      },
      account_data: %{
        events: [
          %{
            type: "m.direct",
            content: %{
              matrix_name(user) => Map.keys(chats)
            }
          }
        ]
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
    conn
    |> json(params)
  end

  defp nickname_from_matrix_id(mid) do
    mid
    |> String.trim_leading("@")
    |> String.replace(":", "@")
    |> String.trim_trailing("@#{Pleroma.Web.Endpoint.host()}")
  end

  def profile(conn, params) do
    nickname =
      params["user_id"]
      |> nickname_from_matrix_id()

    user = User.get_by_nickname(nickname)
    avatar = User.avatar_url(user) |> MediaProxy.url()

    data = %{
      displayname: user.name,
      avatar_url: mxc(avatar)
    }

    conn
    |> json(data)
  end

  def download(conn, params) do
    {:ok, url} = params["file"] |> Base.decode64()

    # This is stupid
    with {:ok, %{status: 200} = env} = Pleroma.HTTP.get(url) do
      conn
      |> send_resp(200, env.body)
    end
  end

  # Not documented, guessing what's expected here
  def joined_groups(conn, _) do
    data = %{
      groups: []
    }

    conn
    |> json(data)
  end

  # Not documented either lololo let's 404
  def room_keys_version(conn, _) do
    conn
    |> put_status(404)
    |> json("Not found")
  end

  # let's just pretend this worked.
  def key_upload(conn, _params) do
    # Enormous numbers so the client will stop trying to upload more
    data = %{
      one_time_key_counts: %{
        curve25519: 100_000,
        signed_curve25519: 2_000_000
      }
    }

    conn
    |> put_status(200)
    |> json(data)
  end

  def capabilities(conn, _) do
    data = %{
      capabilities: %{
        "m.change_password": %{
          enabled: false
        },
        "m.room_versions": %{
          default: "1",
          available: %{
            "1" => "stable"
          }
        }
      }
    }

    conn
    |> json(data)
  end

  # Just pretend it worked
  def set_read_marker(%{assigns: %{user: %{id: user_id}}} = conn, %{
        "m.fully_read" => read_up_to,
        "room_id" => chat_id
      }) do
    with %Chat{user_id: ^user_id} = chat <- Chat.get_by_id(chat_id) do
      MessageReference.set_all_seen_for_chat(chat, read_up_to)
    end

    conn
    |> json(%{})
  end

  def room_members(%{assigns: %{user: %{id: user_id} = user}} = conn, %{"room_id" => chat_id}) do
    with %Chat{user_id: ^user_id, recipient: recipient_id} = chat <- Chat.get_by_id(chat_id),
         %User{} = recipient <- User.get_cached_by_ap_id(recipient_id) do
      membership_events =
        [user, recipient]
        |> membership_events_from_list(chat)

      data = %{
        chunk: membership_events
      }

      conn
      |> json(data)
    end
  end

  # Undocumented
  def publicised_groups(conn, _) do
    data = %{
      groups: %{}
    }

    conn
    |> json(data)
  end

  defp membership_events_from_list(users, chat) do
    users
    |> Enum.map(fn member ->
      avatar = User.avatar_url(member) |> MediaProxy.url()

      %{
        content: %{
          membership: "join",
          avatar_url: mxc(avatar),
          displayname: member.name
        },
        type: "m.room.member",
        event_id: "#{chat.id}/join/#{member.id}",
        room_id: chat.id,
        sender: matrix_name(member),
        origin_ts: DateTime.utc_now() |> DateTime.to_unix(),
        state_key: matrix_name(member)
      }
    end)
  end

  def turn_server(conn, _) do
    conn
    |> put_status(404)
    |> json("not found")
  end

  def send_event(
        %{assigns: %{user: %{id: user_id} = user}} = conn,
        %{
          "msgtype" => "m.text",
          "body" => body,
          "room_id" => chat_id,
          "event_type" => "m.room.message",
          "txn_id" => txn_id
        }
      ) do
    with %Chat{user_id: ^user_id, recipient: recipient_id} = chat <- Chat.get_by_id(chat_id),
         %User{} = recipient <- User.get_cached_by_ap_id(recipient_id),
         {:ok, activity} <- CommonAPI.post_chat_message(user, recipient, body) do
      object = Object.normalize(activity, false)
      cmr = MessageReference.for_chat_and_object(chat, object)

      # Hard to believe, but element (web) does not use the event id to figure out
      # if an event returned via sync is the same as the event we send off, but 
      # instead it uses this transaction id, so if we don't save this (for a
      # little while) we get doubled messages in the frontend.
      Cachex.put(:matrix_cache, "txn_id:#{cmr.id}", txn_id)

      data = %{
        event_id: cmr.id
      }

      conn
      |> json(data)
    end
  end

  def wellknown(conn, _params) do
    conn
    |> put_status(404)
    |> json("not found")
  end

  def typing(conn, _) do
    conn
    |> json(%{})
  end

  def set_account_data(conn, _) do
    conn
    |> json(%{})
  end
end
