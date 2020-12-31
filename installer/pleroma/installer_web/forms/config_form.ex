# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.InstallerWeb.Forms.ConfigForm do
  use Ecto.Schema

  import Ecto.Changeset

  @instance [
    :instance_name,
    :instance_email,
    :instance_notify_email,
    :instance_static_dir
  ]

  @endpoint [
    :endpoint_url_host,
    :endpoint_url_port,
    :endpoint_http_ip,
    :endpoint_http_port
  ]

  @to_file [
    :endpoint_url_scheme,
    :endpoint_secret_key_base,
    :endpoint_signing_salt,
    :joken_default_signer,
    :configurable_from_database
    | @endpoint
  ]

  @primary_key false

  embedded_schema do
    field(:instance_name)
    field(:instance_email)
    field(:instance_notify_email)
    field(:instance_static_dir, :string)

    field(:endpoint_url)
    field(:endpoint_url_host)
    field(:endpoint_url_port, :integer, default: 443)
    field(:endpoint_url_scheme, :string, default: "https")
    field(:endpoint_http_ip)
    field(:endpoint_http_port, :integer)
    field(:endpoint_secret_key_base)
    field(:endpoint_signing_salt)

    field(:local_uploads_dir)

    field(:joken_default_signer)

    field(:web_push_encryption_public_key)
    field(:web_push_encryption_private_key)

    field(:configurable_from_database, :boolean, default: true)
    field(:indexable, :boolean, default: true)
  end

  @spec defaults() :: Ecto.Changeset.t()
  def defaults do
    Ecto.Changeset.change(%__MODULE__{},
      instance_static_dir: "instance/static",
      endpoint_url_port: 443,
      endpoint_http_ip: "127.0.0.1",
      endpoint_http_port: 4000,
      local_uploads_dir: "uploads"
    )
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs \\ %{}) do
    keys =
      @instance ++
        @endpoint ++
        [
          :local_uploads_dir,
          :configurable_from_database,
          :indexable
        ]

    %__MODULE__{}
    |> cast(
      attrs,
      keys
    )
    |> validate_required(keys)
    |> validate_format(:instance_email, Pleroma.User.email_regex())
    |> validate_format(:instance_notify_email, Pleroma.User.email_regex())
    |> validate_change(:endpoint_url, fn :endpoint_url, url ->
      case URI.parse(url) do
        %{scheme: nil} -> [endpoint_url: "url must have scheme"]
        %{host: nil} -> [endpoint_url: "url bad format"]
        _ -> []
      end
    end)
    |> set_url_fields()
    |> add_endpoint_secret()
    |> add_endpoint_signing_salt()
    |> add_joken_default_signer()
    |> add_web_push_keys()
  end

  defp set_url_fields(%{changes: %{endpoint_url: url}} = changeset) do
    uri = URI.parse(url)

    change(changeset,
      endpoint_url_host: uri.host,
      endpoint_url_port: uri.port,
      endpoint_url_scheme: uri.scheme
    )
  end

  defp add_endpoint_secret(changeset) do
    change(changeset, endpoint_secret_key_base: crypt(64))
  end

  defp add_endpoint_signing_salt(changeset) do
    change(changeset, endpoint_signing_salt: crypt(8))
  end

  defp add_joken_default_signer(changeset) do
    change(changeset, joken_default_signer: crypt(64))
  end

  defp crypt(bytes) do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
    |> binary_part(0, bytes)
  end

  defp add_web_push_keys(changeset) do
    {web_push_public_key, web_push_private_key} = :crypto.generate_key(:ecdh, :prime256v1)

    change(changeset,
      web_push_encryption_public_key: Base.url_encode64(web_push_public_key, padding: false),
      web_push_encryption_private_key: Base.url_encode64(web_push_private_key, padding: false)
    )
  end

  @spec save(Ecto.Changeset.t()) ::
          :ok
          | {:error, Ecto.Changeset.t()}
          | {:error, :config_file_not_found}
          | {:error, :file.posix()}
  def save(changeset) do
    config_path = Pleroma.Application.config_path()

    # on this step we expect that config file was already created and contains database credentials,
    # so if file doesn't exist we return error
    if File.exists?(config_path) do
      struct = apply_action(changeset, :create)

      case struct do
        {:ok, struct} ->
          config =
            struct
            |> Map.from_struct()
            |> Map.to_list()

          with :ok <- do_save(config, config_path) do
            generate_robots_txt(config)
          end

        error ->
          error
      end
    else
      {:error, :config_file_not_found}
    end
  end

  defp do_save(config, config_path) do
    if config[:configurable_from_database] do
      save_to_file_and_database(config, config_path)
    else
      save_to_file(config, config_path)
    end
  end

  defp generate_robots_txt(config) do
    templates_dir = Application.app_dir(:pleroma, "priv") <> "/templates"

    Mix.Tasks.Pleroma.Instance.write_robots_txt(
      config[:instance_static_dir],
      config[:indexable],
      templates_dir
    )
  end

  defp save_to_file_and_database(config, config_path) do
    with :ok <-
           write_to_file(config, @to_file, "installer/templates/config_part.eex", config_path) do
      web_push = [
        subject: "mailto:" <> config[:instance_email],
        public_key: config[:web_push_encryption_public_key],
        private_key: config[:web_push_encryption_private_key]
      ]

      changes = [
        %{
          group: :pleroma,
          key: :instance,
          value: Keyword.take(config, @instance)
        },
        %{
          group: :web_push_encryption,
          key: :vapid_details,
          value: web_push
        },
        %{
          group: :pleroma,
          key: Pleroma.Uploaders.Local,
          value: [uploads: config[:local_uploads_dir]]
        }
      ]

      {:ok, _} = Pleroma.Config.Versioning.new_version(changes)

      :ok
    end
  end

  defp save_to_file(config, config_path) do
    keys =
      [
        :local_uploads_dir,
        :web_push_encryption_public_key,
        :web_push_encryption_private_key
        | @instance
      ] ++ @to_file

    write_to_file(config, keys, "installer/templates/config_full.eex", config_path)
  end

  defp write_to_file(config, keys, template, config_path) do
    assigns = Keyword.take(config, keys)

    evaluated = EEx.eval_file(template, assigns)

    File.write(config_path, ["\n", evaluated], [:append])
  end
end
