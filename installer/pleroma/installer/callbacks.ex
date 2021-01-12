defmodule Pleroma.Installer.Callbacks do
  alias Pleroma.Repo

  @callback execute_psql_file(Path.t()) :: {String.t(), non_neg_integer()}
  @callback write_psql_file(Path.t(), iodata()) :: :ok | {:error, :file.posix()}
  @callback start_repo(keyword()) :: :ok | {:error, {:already_started, pid()}} | {:error, term()}
  @callback put_dynamic_repo(atom() | pid()) :: atom() | pid()
  @callback check_connection() :: {:ok, term()} | {:error, term()}
  @callback run_migrations([Path.t()], atom()) :: [non_neg_integer()]
  @callback check_extensions(boolean()) :: :ok | {:error, term()}
  @callback write_config(Path.t(), iodata()) :: :ok | {:error, :file.posix()}

  def execute_psql_file(file_path) do
    System.cmd("sudo", ["-Hu", "postgres", "psql", "-f", file_path])
  end

  def write_psql_file(path, data), do: File.write(path, data)

  def start_repo(config), do: Repo.start_link(config)

  def put_dynamic_repo(repo), do: Repo.put_dynamic_repo(repo)

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

  def write_config(path, content), do: File.write(path, ["\n", content], [:append])
end
