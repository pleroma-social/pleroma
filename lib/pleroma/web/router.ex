# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Router do
  use Pleroma.Web, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
  end

  pipeline :oauth do
    plug(:fetch_session)
    plug(Pleroma.Plugs.OAuthPlug)
    plug(Pleroma.Plugs.UserEnabledPlug)
  end

  pipeline :expect_authentication do
    plug(Pleroma.Plugs.ExpectAuthenticatedCheckPlug)
  end

  pipeline :expect_public_instance_or_authentication do
    plug(Pleroma.Plugs.ExpectPublicOrAuthenticatedCheckPlug)
  end

  pipeline :authenticate do
    plug(Pleroma.Plugs.OAuthPlug)
    plug(Pleroma.Plugs.BasicAuthDecoderPlug)
    plug(Pleroma.Plugs.UserFetcherPlug)
    plug(Pleroma.Plugs.SessionAuthenticationPlug)
    plug(Pleroma.Plugs.LegacyAuthenticationPlug)
    plug(Pleroma.Plugs.AuthenticationPlug)
  end

  pipeline :after_auth do
    plug(Pleroma.Plugs.UserEnabledPlug)
    plug(Pleroma.Plugs.SetUserSessionIdPlug)
    plug(Pleroma.Plugs.EnsureUserKeyPlug)
  end

  pipeline :base_api do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(:authenticate)
    plug(OpenApiSpex.Plug.PutApiSpec, module: Pleroma.Web.ApiSpec)
  end

  pipeline :api do
    plug(:expect_public_instance_or_authentication)
    plug(:base_api)
    plug(:after_auth)
    plug(Pleroma.Plugs.IdempotencyPlug)
  end

  pipeline :authenticated_api do
    plug(:expect_authentication)
    plug(:base_api)
    plug(:after_auth)
    plug(Pleroma.Plugs.EnsureAuthenticatedPlug)
    plug(Pleroma.Plugs.IdempotencyPlug)
  end

  pipeline :admin_api do
    plug(:expect_authentication)
    plug(:base_api)
    plug(Pleroma.Plugs.AdminSecretAuthenticationPlug)
    plug(:after_auth)
    plug(Pleroma.Plugs.EnsureAuthenticatedPlug)
    plug(Pleroma.Plugs.UserIsAdminPlug)
    plug(Pleroma.Plugs.IdempotencyPlug)
  end

  pipeline :mastodon_html do
    plug(:browser)
    plug(:authenticate)
    plug(:after_auth)
  end

  pipeline :pleroma_html do
    plug(:browser)
    plug(:authenticate)
    plug(Pleroma.Plugs.EnsureUserKeyPlug)
  end

  pipeline :well_known do
    plug(:accepts, ["json", "jrd+json", "xml", "xrd+xml"])
  end

  pipeline :config do
    plug(:accepts, ["json", "xml"])
    plug(OpenApiSpex.Plug.PutApiSpec, module: Pleroma.Web.ApiSpec)
  end

  pipeline :pleroma_api do
    plug(:accepts, ["html", "json"])
    plug(OpenApiSpex.Plug.PutApiSpec, module: Pleroma.Web.ApiSpec)
  end

  pipeline :mailbox_preview do
    plug(:accepts, ["html"])

    plug(:put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline' 'unsafe-eval'"
    })
  end

  pipeline :http_signature do
    plug(Pleroma.Web.Plugs.HTTPSignaturePlug)
    plug(Pleroma.Web.Plugs.MappedSignatureToIdentityPlug)
  end

  scope "/api/pleroma", Pleroma.Web.TwitterAPI do
    pipe_through(:pleroma_api)

    get("/password_reset/:token", PasswordController, :reset, as: :reset_password)
    post("/password_reset", PasswordController, :do_reset, as: :reset_password)
    get("/emoji", UtilController, :emoji)
    get("/captcha", UtilController, :captcha)
    get("/healthcheck", UtilController, :healthcheck)
  end

  scope "/api/pleroma", Pleroma.Web do
    pipe_through(:pleroma_api)
    post("/uploader_callback/:upload_path", UploaderController, :callback)
  end

  scope "/api/pleroma/admin", Pleroma.Web.AdminAPI do
    pipe_through(:admin_api)

    post("/users/follow", AdminAPIController, :user_follow)
    post("/users/unfollow", AdminAPIController, :user_unfollow)

    put("/users/disable_mfa", AdminAPIController, :disable_mfa)
    delete("/users", AdminAPIController, :user_delete)
    post("/users", AdminAPIController, :users_create)
    patch("/users/:nickname/toggle_activation", AdminAPIController, :user_toggle_activation)
    patch("/users/activate", AdminAPIController, :user_activate)
    patch("/users/deactivate", AdminAPIController, :user_deactivate)
    patch("/users/approve", AdminAPIController, :user_approve)
    put("/users/tag", AdminAPIController, :tag_users)
    delete("/users/tag", AdminAPIController, :untag_users)

    get("/users/:nickname/permission_group", AdminAPIController, :right_get)
    get("/users/:nickname/permission_group/:permission_group", AdminAPIController, :right_get)

    post("/users/:nickname/permission_group/:permission_group", AdminAPIController, :right_add)

    delete(
      "/users/:nickname/permission_group/:permission_group",
      AdminAPIController,
      :right_delete
    )

    post("/users/permission_group/:permission_group", AdminAPIController, :right_add_multiple)

    delete(
      "/users/permission_group/:permission_group",
      AdminAPIController,
      :right_delete_multiple
    )

    get("/relay", RelayController, :index)
    post("/relay", RelayController, :follow)
    delete("/relay", RelayController, :unfollow)

    post("/users/invite_token", InviteController, :create)
    get("/users/invites", InviteController, :index)
    post("/users/revoke_invite", InviteController, :revoke)
    post("/users/email_invite", InviteController, :email)

    get("/users/:nickname/password_reset", AdminAPIController, :get_password_reset)
    patch("/users/force_password_reset", AdminAPIController, :force_password_reset)
    get("/users/:nickname/credentials", AdminAPIController, :show_user_credentials)
    patch("/users/:nickname/credentials", AdminAPIController, :update_user_credentials)

    get("/users", AdminAPIController, :list_users)
    get("/users/:nickname", AdminAPIController, :user_show)
    get("/users/:nickname/statuses", AdminAPIController, :list_user_statuses)

    get("/instances/:instance/statuses", AdminAPIController, :list_instance_statuses)

    patch("/users/confirm_email", AdminAPIController, :confirm_email)
    patch("/users/resend_confirmation_email", AdminAPIController, :resend_confirmation_email)

    get("/reports", ReportController, :index)
    get("/reports/:id", ReportController, :show)
    patch("/reports", ReportController, :update)
    post("/reports/:id/notes", ReportController, :notes_create)
    delete("/reports/:report_id/notes/:id", ReportController, :notes_delete)

    get("/statuses/:id", StatusController, :show)
    put("/statuses/:id", StatusController, :update)
    delete("/statuses/:id", StatusController, :delete)
    get("/statuses", StatusController, :index)

    get("/config", ConfigController, :show)
    post("/config", ConfigController, :update)
    get("/config/descriptions", ConfigController, :descriptions)
    get("/need_reboot", AdminAPIController, :need_reboot)
    get("/restart", AdminAPIController, :restart)

    get("/moderation_log", AdminAPIController, :list_log)

    post("/reload_emoji", AdminAPIController, :reload_emoji)
    get("/stats", AdminAPIController, :stats)

    get("/oauth_app", OAuthAppController, :index)
    post("/oauth_app", OAuthAppController, :create)
    patch("/oauth_app/:id", OAuthAppController, :update)
    delete("/oauth_app/:id", OAuthAppController, :delete)

    get("/media_proxy_caches", MediaProxyCacheController, :index)
    post("/media_proxy_caches/delete", MediaProxyCacheController, :delete)
    post("/media_proxy_caches/purge", MediaProxyCacheController, :purge)
  end

  scope "/api/pleroma/emoji", Pleroma.Web.PleromaAPI do
    # Modifying packs
    scope "/packs" do
      pipe_through(:admin_api)

      get("/import", EmojiPackController, :import_from_filesystem)
      get("/remote", EmojiPackController, :remote)
      post("/download", EmojiPackController, :download)

      post("/:name", EmojiPackController, :create)
      patch("/:name", EmojiPackController, :update)
      delete("/:name", EmojiPackController, :delete)

      post("/:name/files", EmojiPackController, :add_file)
      patch("/:name/files", EmojiPackController, :update_file)
      delete("/:name/files", EmojiPackController, :delete_file)
    end

    # Pack info / downloading
    scope "/packs" do
      pipe_through(:api)
      get("/", EmojiPackController, :index)
      get("/:name", EmojiPackController, :show)
      get("/:name/archive", EmojiPackController, :archive)
    end
  end

  scope "/", Pleroma.Web.TwitterAPI do
    pipe_through(:pleroma_html)

    post("/main/ostatus", UtilController, :remote_subscribe)
    get("/ostatus_subscribe", RemoteFollowController, :follow)

    post("/ostatus_subscribe", RemoteFollowController, :do_follow)
  end

  scope "/api/pleroma", Pleroma.Web.TwitterAPI do
    pipe_through(:authenticated_api)

    post("/change_email", UtilController, :change_email)
    post("/change_password", UtilController, :change_password)
    post("/delete_account", UtilController, :delete_account)
    put("/notification_settings", UtilController, :update_notificaton_settings)
    post("/disable_account", UtilController, :disable_account)

    post("/blocks_import", UtilController, :blocks_import)
    post("/follow_import", UtilController, :follow_import)
  end

  scope "/api/pleroma", Pleroma.Web.PleromaAPI do
    pipe_through(:authenticated_api)

    get("/accounts/mfa", TwoFactorAuthenticationController, :settings)
    get("/accounts/mfa/backup_codes", TwoFactorAuthenticationController, :backup_codes)
    get("/accounts/mfa/setup/:method", TwoFactorAuthenticationController, :setup)
    post("/accounts/mfa/confirm/:method", TwoFactorAuthenticationController, :confirm)
    delete("/accounts/mfa/:method", TwoFactorAuthenticationController, :disable)
  end

  scope "/oauth", Pleroma.Web.OAuth do
    scope [] do
      pipe_through(:oauth)
      get("/authorize", OAuthController, :authorize)
    end

    post("/authorize", OAuthController, :create_authorization)
    post("/token", OAuthController, :token_exchange)
    post("/revoke", OAuthController, :token_revoke)
    get("/registration_details", OAuthController, :registration_details)

    post("/mfa/challenge", MFAController, :challenge)
    post("/mfa/verify", MFAController, :verify, as: :mfa_verify)
    get("/mfa", MFAController, :show)

    scope [] do
      pipe_through(:browser)

      get("/prepare_request", OAuthController, :prepare_request)
      get("/:provider", OAuthController, :request)
      get("/:provider/callback", OAuthController, :callback)
      post("/register", OAuthController, :register)
    end
  end

  scope "/api/v1/pleroma", Pleroma.Web.PleromaAPI do
    pipe_through(:api)

    get("/statuses/:id/reactions/:emoji", EmojiReactionController, :index)
    get("/statuses/:id/reactions", EmojiReactionController, :index)
  end

  scope "/api/v1/pleroma", Pleroma.Web.PleromaAPI do
    scope [] do
      pipe_through(:authenticated_api)

      post("/chats/by-account-id/:id", ChatController, :create)
      get("/chats", ChatController, :index)
      get("/chats/:id", ChatController, :show)
      get("/chats/:id/messages", ChatController, :messages)
      post("/chats/:id/messages", ChatController, :post_chat_message)
      delete("/chats/:id/messages/:message_id", ChatController, :delete_message)
      post("/chats/:id/read", ChatController, :mark_as_read)
      post("/chats/:id/messages/:message_id/read", ChatController, :mark_message_as_read)

      get("/conversations/:id/statuses", ConversationController, :statuses)
      get("/conversations/:id", ConversationController, :show)
      post("/conversations/read", ConversationController, :mark_as_read)
      patch("/conversations/:id", ConversationController, :update)

      put("/statuses/:id/reactions/:emoji", EmojiReactionController, :create)
      delete("/statuses/:id/reactions/:emoji", EmojiReactionController, :delete)
      post("/notifications/read", NotificationController, :mark_as_read)

      get("/mascot", MascotController, :show)
      put("/mascot", MascotController, :update)

      post("/scrobble", ScrobbleController, :create)
    end

    scope [] do
      pipe_through(:api)
      get("/accounts/:id/favourites", AccountController, :favourites)
    end

    scope [] do
      pipe_through(:authenticated_api)

      post("/accounts/:id/subscribe", AccountController, :subscribe)
      post("/accounts/:id/unsubscribe", AccountController, :unsubscribe)
    end

    post("/accounts/confirmation_resend", AccountController, :confirmation_resend)
  end

  scope "/api/v1/pleroma", Pleroma.Web.PleromaAPI do
    pipe_through(:api)
    get("/accounts/:id/scrobbles", ScrobbleController, :index)
  end

  scope "/api/v1", Pleroma.Web.MastodonAPI do
    pipe_through(:authenticated_api)

    get("/accounts/verify_credentials", AccountController, :verify_credentials)
    patch("/accounts/update_credentials", AccountController, :update_credentials)

    get("/accounts/relationships", AccountController, :relationships)
    get("/accounts/:id/lists", AccountController, :lists)
    get("/accounts/:id/identity_proofs", AccountController, :identity_proofs)
    get("/endorsements", AccountController, :endorsements)
    get("/blocks", AccountController, :blocks)
    get("/mutes", AccountController, :mutes)

    post("/follows", AccountController, :follow_by_uri)
    post("/accounts/:id/follow", AccountController, :follow)
    post("/accounts/:id/unfollow", AccountController, :unfollow)
    post("/accounts/:id/block", AccountController, :block)
    post("/accounts/:id/unblock", AccountController, :unblock)
    post("/accounts/:id/mute", AccountController, :mute)
    post("/accounts/:id/unmute", AccountController, :unmute)

    get("/apps/verify_credentials", AppController, :verify_credentials)

    get("/conversations", ConversationController, :index)
    post("/conversations/:id/read", ConversationController, :mark_as_read)

    get("/domain_blocks", DomainBlockController, :index)
    post("/domain_blocks", DomainBlockController, :create)
    delete("/domain_blocks", DomainBlockController, :delete)

    get("/filters", FilterController, :index)

    post("/filters", FilterController, :create)
    get("/filters/:id", FilterController, :show)
    put("/filters/:id", FilterController, :update)
    delete("/filters/:id", FilterController, :delete)

    get("/follow_requests", FollowRequestController, :index)
    post("/follow_requests/:id/authorize", FollowRequestController, :authorize)
    post("/follow_requests/:id/reject", FollowRequestController, :reject)

    get("/lists", ListController, :index)
    get("/lists/:id", ListController, :show)
    get("/lists/:id/accounts", ListController, :list_accounts)

    delete("/lists/:id", ListController, :delete)
    post("/lists", ListController, :create)
    put("/lists/:id", ListController, :update)
    post("/lists/:id/accounts", ListController, :add_to_list)
    delete("/lists/:id/accounts", ListController, :remove_from_list)

    get("/markers", MarkerController, :index)
    post("/markers", MarkerController, :upsert)

    post("/media", MediaController, :create)
    get("/media/:id", MediaController, :show)
    put("/media/:id", MediaController, :update)

    get("/notifications", NotificationController, :index)
    get("/notifications/:id", NotificationController, :show)

    post("/notifications/:id/dismiss", NotificationController, :dismiss)
    post("/notifications/clear", NotificationController, :clear)
    delete("/notifications/destroy_multiple", NotificationController, :destroy_multiple)
    # Deprecated: was removed in Mastodon v3, use `/notifications/:id/dismiss` instead
    post("/notifications/dismiss", NotificationController, :dismiss_via_body)

    post("/polls/:id/votes", PollController, :vote)

    post("/reports", ReportController, :create)

    get("/scheduled_statuses", ScheduledActivityController, :index)
    get("/scheduled_statuses/:id", ScheduledActivityController, :show)

    put("/scheduled_statuses/:id", ScheduledActivityController, :update)
    delete("/scheduled_statuses/:id", ScheduledActivityController, :delete)

    # Unlike `GET /api/v1/accounts/:id/favourites`, demands authentication
    get("/favourites", StatusController, :favourites)
    get("/bookmarks", StatusController, :bookmarks)

    post("/statuses", StatusController, :create)
    delete("/statuses/:id", StatusController, :delete)
    post("/statuses/:id/reblog", StatusController, :reblog)
    post("/statuses/:id/unreblog", StatusController, :unreblog)
    post("/statuses/:id/favourite", StatusController, :favourite)
    post("/statuses/:id/unfavourite", StatusController, :unfavourite)
    post("/statuses/:id/pin", StatusController, :pin)
    post("/statuses/:id/unpin", StatusController, :unpin)
    post("/statuses/:id/bookmark", StatusController, :bookmark)
    post("/statuses/:id/unbookmark", StatusController, :unbookmark)
    post("/statuses/:id/mute", StatusController, :mute_conversation)
    post("/statuses/:id/unmute", StatusController, :unmute_conversation)

    post("/push/subscription", SubscriptionController, :create)
    get("/push/subscription", SubscriptionController, :show)
    put("/push/subscription", SubscriptionController, :update)
    delete("/push/subscription", SubscriptionController, :delete)

    get("/suggestions", SuggestionController, :index)

    get("/timelines/home", TimelineController, :home)
    get("/timelines/direct", TimelineController, :direct)
    get("/timelines/list/:list_id", TimelineController, :list)
  end

  scope "/api/web", Pleroma.Web do
    pipe_through(:authenticated_api)

    # Backend-obscure settings blob for MastoFE, don't parse/reuse elsewhere
    put("/settings", MastoFEController, :put_settings)
  end

  scope "/api/v1", Pleroma.Web.MastodonAPI do
    pipe_through(:api)

    get("/accounts/search", SearchController, :account_search)
    get("/search", SearchController, :search)

    get("/accounts/:id/statuses", AccountController, :statuses)
    get("/accounts/:id/followers", AccountController, :followers)
    get("/accounts/:id/following", AccountController, :following)
    get("/accounts/:id", AccountController, :show)

    post("/accounts", AccountController, :create)

    get("/instance", InstanceController, :show)
    get("/instance/peers", InstanceController, :peers)

    post("/apps", AppController, :create)

    get("/statuses", StatusController, :index)
    get("/statuses/:id", StatusController, :show)
    get("/statuses/:id/context", StatusController, :context)
    get("/statuses/:id/card", StatusController, :card)
    get("/statuses/:id/favourited_by", StatusController, :favourited_by)
    get("/statuses/:id/reblogged_by", StatusController, :reblogged_by)

    get("/custom_emojis", CustomEmojiController, :index)

    get("/trends", MastodonAPIController, :empty_array)

    get("/timelines/public", TimelineController, :public)
    get("/timelines/tag/:tag", TimelineController, :hashtag)

    get("/polls/:id", PollController, :show)
  end

  scope "/api/v2", Pleroma.Web.MastodonAPI do
    pipe_through(:api)
    get("/search", SearchController, :search2)

    post("/media", MediaController, :create2)
  end

  scope "/api", Pleroma.Web do
    pipe_through(:config)

    get("/pleroma/frontend_configurations", TwitterAPI.UtilController, :frontend_configurations)
  end

  scope "/api", Pleroma.Web do
    pipe_through(:api)

    get(
      "/account/confirm_email/:user_id/:token",
      TwitterAPI.Controller,
      :confirm_email,
      as: :confirm_email
    )
  end

  scope "/api" do
    pipe_through(:base_api)

    get("/openapi", OpenApiSpex.Plug.RenderSpec, [])
  end

  scope "/api", Pleroma.Web, as: :authenticated_twitter_api do
    pipe_through(:authenticated_api)

    get("/oauth_tokens", TwitterAPI.Controller, :oauth_tokens)
    delete("/oauth_tokens/:id", TwitterAPI.Controller, :revoke_token)

    post(
      "/qvitter/statuses/notifications/read",
      TwitterAPI.Controller,
      :mark_notifications_as_read
    )
  end

  pipeline :ostatus do
    plug(:accepts, ["html", "xml", "rss", "atom", "activity+json", "json"])
    plug(Pleroma.Plugs.StaticFEPlug)
  end

  pipeline :oembed do
    plug(:accepts, ["json", "xml"])
  end

  scope "/", Pleroma.Web do
    pipe_through([:ostatus, :http_signature])

    get("/objects/:uuid", OStatus.OStatusController, :object)
    get("/activities/:uuid", OStatus.OStatusController, :activity)
    get("/notice/:id", OStatus.OStatusController, :notice)
    get("/notice/:id/embed_player", OStatus.OStatusController, :notice_player)

    # Mastodon compatibility routes
    get("/users/:nickname/statuses/:id", OStatus.OStatusController, :object)
    get("/users/:nickname/statuses/:id/activity", OStatus.OStatusController, :activity)

    get("/users/:nickname/feed", Feed.UserController, :feed, as: :user_feed)
    get("/users/:nickname", Feed.UserController, :feed_redirect, as: :user_feed)

    get("/tags/:tag", Feed.TagController, :feed, as: :tag_feed)
  end

  scope "/", Pleroma.Web do
    pipe_through(:browser)
    get("/mailer/unsubscribe/:token", Mailer.SubscriptionController, :unsubscribe)
  end

  pipeline :ap_service_actor do
    plug(:accepts, ["activity+json", "json"])
  end

  # Server to Server (S2S) AP interactions
  pipeline :activitypub do
    plug(:ap_service_actor)
    plug(:http_signature)
  end

  # Client to Server (C2S) AP interactions
  pipeline :activitypub_client do
    plug(:ap_service_actor)
    plug(:fetch_session)
    plug(:authenticate)
    plug(:after_auth)
  end

  scope "/", Pleroma.Web.ActivityPub do
    pipe_through([:activitypub_client])

    get("/api/ap/whoami", ActivityPubController, :whoami)
    get("/users/:nickname/inbox", ActivityPubController, :read_inbox)

    get("/users/:nickname/outbox", ActivityPubController, :outbox)
    post("/users/:nickname/outbox", ActivityPubController, :update_outbox)
    post("/api/ap/upload_media", ActivityPubController, :upload_media)

    # The following two are S2S as well, see `ActivityPub.fetch_follow_information_for_user/1`:
    get("/users/:nickname/followers", ActivityPubController, :followers)
    get("/users/:nickname/following", ActivityPubController, :following)
  end

  scope "/", Pleroma.Web.ActivityPub do
    pipe_through(:activitypub)
    post("/inbox", ActivityPubController, :inbox)
    post("/users/:nickname/inbox", ActivityPubController, :inbox)
  end

  scope "/relay", Pleroma.Web.ActivityPub do
    pipe_through(:ap_service_actor)

    get("/", ActivityPubController, :relay)

    scope [] do
      pipe_through(:http_signature)
      post("/inbox", ActivityPubController, :inbox)
    end

    get("/following", ActivityPubController, :relay_following)
    get("/followers", ActivityPubController, :relay_followers)
  end

  scope "/internal/fetch", Pleroma.Web.ActivityPub do
    pipe_through(:ap_service_actor)

    get("/", ActivityPubController, :internal_fetch)
    post("/inbox", ActivityPubController, :inbox)
  end

  scope "/.well-known", Pleroma.Web do
    pipe_through(:well_known)

    get("/host-meta", WebFinger.WebFingerController, :host_meta)
    get("/webfinger", WebFinger.WebFingerController, :webfinger)
    get("/nodeinfo", Nodeinfo.NodeinfoController, :schemas)
  end

  scope "/nodeinfo", Pleroma.Web do
    get("/:version", Nodeinfo.NodeinfoController, :nodeinfo)
  end

  scope "/", Pleroma.Web do
    pipe_through(:api)

    get("/web/manifest.json", MastoFEController, :manifest)
  end

  scope "/", Pleroma.Web do
    pipe_through(:mastodon_html)

    get("/web/login", MastodonAPI.AuthController, :login)
    delete("/auth/sign_out", MastodonAPI.AuthController, :logout)

    post("/auth/password", MastodonAPI.AuthController, :password_reset)

    get("/web/*path", MastoFEController, :index)

    get("/embed/:id", EmbedController, :show)
  end

  scope "/proxy/", Pleroma.Web.MediaProxy do
    get("/:sig/:url", MediaProxyController, :remote)
    get("/:sig/:url/:filename", MediaProxyController, :remote)
  end

  if Pleroma.Config.get(:env) == :dev do
    scope "/dev" do
      pipe_through([:mailbox_preview])

      forward("/mailbox", Plug.Swoosh.MailboxPreview, base_path: "/dev/mailbox")
    end
  end

  # Test-only routes needed to test action dispatching and plug chain execution
  if Pleroma.Config.get(:env) == :test do
    @test_actions [
      :do_oauth_check,
      :fallback_oauth_check,
      :skip_oauth_check,
      :fallback_oauth_skip_publicity_check,
      :skip_oauth_skip_publicity_check,
      :missing_oauth_check_definition
    ]

    scope "/test/api", Pleroma.Tests do
      pipe_through(:api)

      for action <- @test_actions do
        get("/#{action}", AuthTestController, action)
      end
    end

    scope "/test/authenticated_api", Pleroma.Tests do
      pipe_through(:authenticated_api)

      for action <- @test_actions do
        get("/#{action}", AuthTestController, action)
      end
    end
  end

  scope "/_matrix", Pleroma.Web do
    get("/client/versions", MatrixController, :client_versions)
    get("/client/r0/login", MatrixController, :login_info)
    post("/client/r0/login", MatrixController, :login)
  end

  scope "/", Pleroma.Web.MongooseIM do
    get("/user_exists", MongooseIMController, :user_exists)
    get("/check_password", MongooseIMController, :check_password)
  end

  scope "/", Fallback do
    get("/registration/:token", RedirectController, :registration_page)
    get("/:maybe_nickname_or_id", RedirectController, :redirector_with_meta)
    get("/api*path", RedirectController, :api_not_implemented)
    get("/*path", RedirectController, :redirector_with_preload)

    options("/*path", RedirectController, :empty)
  end
end
