# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application.RequirementsTest do
  use Pleroma.DataCase

  import ExUnit.CaptureLog
  import Mock

  alias Pleroma.Application.Requirements
  alias Pleroma.Config
  alias Pleroma.Emails.Mailer
  alias Pleroma.Repo

  describe "check_repo_pool_size!/1" do
    test "raises if the pool size is unexpected" do
      clear_config([Pleroma.Repo, :pool_size], 11)
      clear_config([:dangerzone, :override_repo_pool_size], false)

      assert_raise Requirements.VerifyError,
                   "Repo.pool_size different than recommended value.",
                   fn ->
                     capture_log(&Requirements.verify!/0)
                   end
    end

    test "doesn't raise if the pool size is unexpected but the respective flag is set" do
      clear_config([Pleroma.Repo, :pool_size], 11)
      clear_config([:dangerzone, :override_repo_pool_size], true)

      assert Requirements.verify!() == :ok
    end
  end

  describe "check_welcome_message_config!/1" do
    setup do: clear_config([:welcome])
    setup do: clear_config([Mailer])

    test "raises if welcome email enabled but mail disabled" do
      Config.put([:welcome, :email, :enabled], true)
      Config.put([Mailer, :enabled], false)

      assert_raise Requirements.VerifyError, "The mail disabled.", fn ->
        capture_log(&Requirements.verify!/0)
      end
    end
  end

  describe "check_confirmation_accounts!" do
    setup_with_mocks([
      {Requirements, [:passthrough],
       [
         check_migrations_applied: fn _ -> :ok end
       ]}
    ]) do
      :ok
    end

    setup do: clear_config([:instance, :account_activation_required])

    test "raises if account confirmation is required but mailer isn't enable" do
      Config.put([:instance, :account_activation_required], true)
      Config.put([Mailer, :enabled], false)

      assert_raise Requirements.VerifyError,
                   "Account activation enabled, but Mailer is disabled. Cannot send confirmation emails.",
                   fn ->
                     capture_log(&Requirements.verify!/0)
                   end
    end

    test "doesn't do anything if account confirmation is disabled" do
      Config.put([:instance, :account_activation_required], false)
      Config.put([Mailer, :enabled], false)
      assert Requirements.verify!() == :ok
    end

    test "doesn't do anything if account confirmation is required and mailer is enabled" do
      Config.put([:instance, :account_activation_required], true)
      Config.put([Mailer, :enabled], true)
      assert Requirements.verify!() == :ok
    end
  end

  describe "check_rum!" do
    setup_with_mocks([
      {Requirements, [:passthrough], [check_migrations_applied: fn _ -> :ok end]}
    ]) do
      :ok
    end

    setup do: clear_config([:database, :rum_enabled])

    test "raises if rum is enabled and detects unapplied rum migrations" do
      Config.put([:database, :rum_enabled], true)

      with_mocks([{Repo, [:passthrough], [exists?: fn _, _ -> false end]}]) do
        assert_raise Requirements.VerifyError,
                     "Unapplied RUM Migrations detected",
                     fn ->
                       capture_log(&Requirements.verify!/0)
                     end
      end
    end

    test "raises if rum is disabled and detects rum migrations" do
      Config.put([:database, :rum_enabled], false)

      with_mocks([{Repo, [:passthrough], [exists?: fn _, _ -> true end]}]) do
        assert_raise Requirements.VerifyError,
                     "RUM Migrations detected",
                     fn ->
                       capture_log(&Requirements.verify!/0)
                     end
      end
    end

    test "doesn't do anything if rum enabled and applied migrations" do
      Config.put([:database, :rum_enabled], true)

      with_mocks([{Repo, [:passthrough], [exists?: fn _, _ -> true end]}]) do
        assert Requirements.verify!() == :ok
      end
    end

    test "doesn't do anything if rum disabled" do
      Config.put([:database, :rum_enabled], false)

      with_mocks([{Repo, [:passthrough], [exists?: fn _, _ -> false end]}]) do
        assert Requirements.verify!() == :ok
      end
    end
  end

  describe "check_migrations_applied" do
    setup_with_mocks([
      {Ecto.Migrator, [],
       [
         with_repo: fn repo, fun -> passthrough([repo, fun]) end,
         migrations: fn Repo ->
           [
             {:up, 20_191_128_153_944, "fix_missing_following_count"},
             {:up, 20_191_203_043_610, "create_report_notes"},
             {:down, 20_191_220_174_645, "add_scopes_to_pleroma_feo_auth_records"}
           ]
         end
       ]}
    ]) do
      :ok
    end

    setup do: clear_config([:i_am_aware_this_may_cause_data_loss, :disable_migration_check])

    test "raises if it detects unapplied migrations" do
      assert_raise Requirements.VerifyError,
                   "Unapplied Migrations detected",
                   fn ->
                     capture_log(&Requirements.verify!/0)
                   end
    end

    test "doesn't do anything if disabled" do
      Config.put([:i_am_aware_this_may_cause_data_loss, :disable_migration_check], true)

      assert :ok == Requirements.verify!()
    end
  end
end