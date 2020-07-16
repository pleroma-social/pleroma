# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.AdminAPI.ConfigController do
  use Pleroma.Web, :controller

  import Pleroma.Web.ControllerHelper, only: [json_response: 3]

  alias Pleroma.Application
  alias Pleroma.Config
  alias Pleroma.ConfigDB
  alias Pleroma.Web.Plugs.OAuthScopesPlug

  plug(Pleroma.Web.ApiSpec.CastAndValidate)
  plug(OAuthScopesPlug, %{scopes: ["write"], admin: true} when action in [:update, :rollback])

  plug(
    OAuthScopesPlug,
    %{scopes: ["read"], admin: true}
    when action in [:show, :descriptions, :versions]
  )

  plug(:check_possibility_configuration_from_database when action != :descriptions)

  action_fallback(Pleroma.Web.AdminAPI.FallbackController)

  defdelegate open_api_operation(action), to: Pleroma.Web.ApiSpec.Admin.ConfigOperation

  def descriptions(conn, _params) do
    descriptions = Enum.filter(Pleroma.Docs.JSON.compiled_descriptions(), &whitelisted_config?/1)

    json(conn, descriptions)
  end

  def show(conn, %{only_db: true}) do
    configs = ConfigDB.all_with_db()

    render(conn, "index.json", %{
      configs: configs,
      need_reboot: Application.ConfigDependentDeps.need_reboot?()
    })
  end

  def show(conn, _params) do
    defaults = Config.Holder.default_config()
    changes = ConfigDB.all_with_db()

    {changes_values_merged_with_defaults, remaining_defaults} =
      ConfigDB.reduce_defaults_and_merge_with_changes(changes, defaults)

    changes_merged_with_defaults =
      ConfigDB.from_keyword_to_structs(remaining_defaults, changes_values_merged_with_defaults)

    render(conn, "index.json", %{
      configs: changes_merged_with_defaults,
      need_reboot: Application.ConfigDependentDeps.need_reboot?()
    })
  end

  def update(%{body_params: %{configs: configs}} = conn, _) do
    result =
      configs
      |> Enum.filter(&whitelisted_config?/1)
      |> Enum.map(&Config.Converter.to_elixir_types/1)
      |> Config.Versioning.new_version()

    case result do
      {:ok, changes} ->
        inserts_and_deletions =
          changes
          |> Enum.reduce([], fn
            {{operation, _, _}, %ConfigDB{} = change}, acc
            when operation in [:insert_or_update, :delete_or_update] ->
              if Ecto.get_meta(change, :state) == :deleted do
                [change | acc]
              else
                if change.group == :pleroma and
                     change.key in ConfigDB.pleroma_not_keyword_values() do
                  [%{change | db: [change.key]} | acc]
                else
                  [%{change | db: Keyword.keys(change.value)} | acc]
                end
              end

            _, acc ->
              acc
          end)

        Application.Environment.update(inserts_and_deletions)

        render(conn, "index.json", %{
          configs: Enum.reject(inserts_and_deletions, &(Ecto.get_meta(&1, :state) == :deleted)),
          need_reboot: Application.ConfigDependentDeps.need_reboot?()
        })

      {:error, error} ->
        {:error, "Updating config failed: #{inspect(error)}"}

      {:error, _, {error, operation}, _} ->
        {:error,
         "Updating config failed: #{inspect(error)}, group: #{operation[:group]}, key: #{
           operation[:key]
         }, value: #{inspect(operation[:value])}"}
    end
  end

  def rollback(conn, %{id: id}) do
    case Config.Versioning.rollback_by_id(id) do
      {:ok, _} ->
        json_response(conn, :no_content, "")

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, error} ->
        {:error, "Rollback is not possible: #{inspect(error)}"}

      {:error, _, {error, operation}, _} ->
        {:error,
         "Rollback is not possible, backup restore error: #{inspect(error)}, operation error: #{
           inspect(operation)
         }"}
    end
  end

  def versions(conn, _) do
    versions = Pleroma.Config.Version.all()

    render(conn, "index.json", %{versions: versions})
  end

  defp check_possibility_configuration_from_database(conn, _) do
    if Config.get(:configurable_from_database) do
      conn
    else
      Pleroma.Web.AdminAPI.FallbackController.call(
        conn,
        {:error, "To use this endpoint you need to enable configuration from database."}
      )
      |> halt()
    end
  end

  defp whitelisted_config?(group, key) do
    if whitelisted_configs = Config.get(:database_config_whitelist) do
      Enum.any?(whitelisted_configs, fn
        {whitelisted_group} ->
          group == inspect(whitelisted_group)

        {whitelisted_group, whitelisted_key} ->
          group == inspect(whitelisted_group) && key == inspect(whitelisted_key)
      end)
    else
      true
    end
  end

  defp whitelisted_config?(%{group: group, key: key}) do
    whitelisted_config?(group, key)
  end

  defp whitelisted_config?(%{group: group} = config) do
    whitelisted_config?(group, config[:key])
  end
end
