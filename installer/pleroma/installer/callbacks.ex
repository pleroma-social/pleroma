defmodule Pleroma.Installer.Callbacks do
  alias Pleroma.Repo

  @callback execute_psql_file(Path.t()) :: {String.t(), non_neg_integer()}
  @callback write(Path.t(), iodata()) :: :ok | {:error, :file.posix()}
  @callback write(Path.t(), iodata(), [atom()]) :: :ok | {:error, :file.posix()}
  @callback start_dynamic_repo(keyword()) ::
              {:ok, pid()} | {:error, {:already_started, pid()}} | {:error, term()}
  @callback check_connection() :: {:ok, term()} | {:error, term()}
  @callback run_migrations([Path.t()], atom()) :: [non_neg_integer()]
  @callback check_extensions(boolean()) :: :ok | {:error, term()}

  defdelegate write(path, content, modes \\ []), to: File

  def execute_psql_file(file_path) do
    [command, args] = Pleroma.Config.get([:installer, :psql_cmd_args])
    System.cmd(command, args ++ [file_path])
  end

  def start_dynamic_repo(config) do
    config =
      Keyword.put(config, :name, Pleroma.InstallerWeb.Forms.CredentialsForm.installer_repo())

    with {:ok, pid} = result <- Repo.start_link(config) do
      Repo.put_dynamic_repo(pid)
      result
    end
  end

  def check_connection, do: Repo.query("SELECT 1")

  def run_migrations(paths, repo) do
    Ecto.Migrator.run(Repo, paths, :up, all: true, dynamic_repo: repo)
  end

  def check_extensions(rum_enabled?) do
    default = ["citext", "pg_trgm", "uuid-ossp"]

    required = if rum_enabled?, do: ["rum" | default], else: default

    with {:ok, %{rows: extensions}} <- Repo.query("SELECT pg_available_extensions();") do
      extensions = Enum.map(extensions, fn [{name, _, _}] -> name end)

      not_installed =
        Enum.reduce(required, [], fn ext, acc ->
          if ext in extensions do
            acc
          else
            [ext | acc]
          end
        end)

      if not_installed == [] do
        :ok
      else
        {:error, "These extensions are not installed: #{Enum.join(not_installed, ",")}"}
      end
    end
  end
end
