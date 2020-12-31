defmodule Pleroma.Installer.System do
  @callback execute_psql_file(Path.t()) :: {String.t(), non_neg_integer()}

  def execute_psql_file(file_path) do
    System.cmd("sudo", ["-Hu", "postgres", "psql", "-f", file_path])
  end
end
