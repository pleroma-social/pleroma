# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Application do
  use Application

  alias Pleroma.Config

  require Logger

  @name Mix.Project.config()[:name]
  @version Mix.Project.config()[:version]
  @repository Mix.Project.config()[:source_url]
  @env Mix.env()
  @dynamic_supervisor Pleroma.Application.Supervisor

  @type env() :: :test | :benchmark | :dev | :prod

  def name, do: @name
  def version, do: @version
  def named_version, do: @name <> " " <> @version
  def repository, do: @repository
  def dynamic_supervisor, do: @dynamic_supervisor

  @spec user_agent() :: String.t()
  def user_agent do
    if Process.whereis(Pleroma.Web.Endpoint) do
      case Config.get([:http, :user_agent], :default) do
        :default ->
          info = "#{Pleroma.Web.base_url()} <#{Config.get([:instance, :email], "")}>"
          named_version() <> "; " <> info

        custom ->
          custom
      end
    else
      # fallback, if endpoint is not started yet
      "Pleroma Data Loader"
    end
  end

  @spec config_path() :: Path.t()
  def config_path do
    if Config.get(:release) do
      Config.get(:config_path)
    else
      Config.get(:config_path_in_test) || "config/#{@env}.secret.exs"
    end
  end

  @doc """
  Checks that config file exists and starts application, otherwise starts web UI for configuration.
  Under main supervisor is started DynamicSupervisor, which later starts pleroma startup dependencies.
  Pleroma start is splitted into three `phases`:
    - running prestart requirements (runtime compilation, warnings, deprecations, monitoring, etc.)
    - loading and updating environment (if database config is used and enabled)
    - starting dependencies
  """
  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: @dynamic_supervisor},
      {Pleroma.Application.ConfigDependentDeps, [dynamic_supervisor: @dynamic_supervisor]}
    ]

    {:ok, main_supervisor} =
      Supervisor.start_link(children, strategy: :one_for_one, name: Pleroma.Supervisor)

    if @env == :test or File.exists?(Pleroma.Application.config_path()) do
      {:ok, _} = DynamicSupervisor.start_child(@dynamic_supervisor, Pleroma.Repo)
      :ok = start_pleroma()
    else
      DynamicSupervisor.start_child(
        @dynamic_supervisor,
        Pleroma.InstallerWeb.Endpoint
      )

      token = Ecto.UUID.generate()

      Pleroma.Config.put(:installer_token, token)

      installer_port =
        Pleroma.InstallerWeb.Endpoint
        |> Pleroma.Config.get()
        |> get_in([:http, :port])

      ip =
        with {:ok, ip} <- Pleroma.Helpers.ServerIPHelper.real_ip() do
          ip
        else
          _ -> "IP not found"
        end

      Logger.warn("Access installer at http://#{ip}:#{installer_port}/?token=#{token}")
    end

    {:ok, main_supervisor}
  end

  defp start_pleroma do
    run_prestart_requirements()

    Pleroma.Application.Environment.load_from_db_and_update()

    Pleroma.Application.StartUpDependencies.start_all(@env)
  end

  @spec stop_installer_and_start_pleroma() :: {:ok, pid()}
  def stop_installer_and_start_pleroma do
    Pleroma.Application.config_path()
    |> Pleroma.Application.Environment.update()

    start_pleroma()

    Task.start(fn ->
      Process.sleep(100)

      installer_endpoint = Process.whereis(Pleroma.InstallerWeb.Endpoint)

      DynamicSupervisor.terminate_child(
        @dynamic_supervisor,
        installer_endpoint
      )
    end)
  end

  defp run_prestart_requirements do
    # Scrubbers are compiled at runtime and therefore will cause a conflict
    # every time the application is restarted, so we disable module
    # conflicts at runtime
    Code.compiler_options(ignore_module_conflict: true)
    # Disable warnings_as_errors at runtime, it breaks Phoenix live reload
    # due to protocol consolidation warnings
    Code.compiler_options(warnings_as_errors: false)

    # compilation in runtime
    Pleroma.HTML.compile_scrubbers()
    compile_custom_modules()
    Pleroma.Docs.JSON.compile()

    # telemetry and prometheus
    Pleroma.Telemetry.Logger.attach()
    setup_instrumenters()

    Config.Holder.save_default()

    Config.DeprecationWarnings.warn()
    Pleroma.Web.Plugs.HTTPSecurityPlug.warn_if_disabled()

    limiters_setup()

    set_postgres_server_version()

    Pleroma.Application.Requirements.verify!()
  end

  defp set_postgres_server_version do
    version =
      with %{rows: [[version]]} <- Ecto.Adapters.SQL.query!(Pleroma.Repo, "show server_version"),
           {num, _} <- Float.parse(version) do
        num
      else
        e ->
          Logger.warn(
            "Could not get the postgres version: #{inspect(e)}.\nSetting the default value of 9.6"
          )

          9.6
      end

    :persistent_term.put({Pleroma.Repo, :postgres_version}, version)
  end

  defp compile_custom_modules do
    dir = Config.get([:modules, :runtime_dir])

    if dir && File.exists?(dir) do
      dir
      |> Pleroma.Utils.compile_dir()
      |> case do
        {:error, _errors, _warnings} ->
          raise "Invalid custom modules"

        {:ok, modules, _warnings} ->
          if @env != :test do
            Enum.each(modules, fn mod ->
              Logger.info("Custom module loaded: #{inspect(mod)}")
            end)
          end

          :ok
      end
    end
  end

  defp setup_instrumenters do
    require Prometheus.Registry

    if Application.get_env(:prometheus, Pleroma.Repo.Instrumenter) do
      :ok =
        :telemetry.attach(
          "prometheus-ecto",
          [:pleroma, :repo, :query],
          &Pleroma.Repo.Instrumenter.handle_event/4,
          %{}
        )

      Pleroma.Repo.Instrumenter.setup()
    end

    Pleroma.Web.Endpoint.MetricsExporter.setup()
    Pleroma.Web.Endpoint.PipelineInstrumenter.setup()

    # Note: disabled until prometheus-phx is integrated into prometheus-phoenix:
    # Pleroma.Web.Endpoint.Instrumenter.setup()
    PrometheusPhx.setup()
  end

  @spec limiters_setup() :: :ok
  def limiters_setup do
    [Pleroma.Web.RichMedia.Helpers, Pleroma.Web.MediaProxy]
    |> Enum.each(&ConcurrentLimiter.new(&1, 1, 0))
  end
end
