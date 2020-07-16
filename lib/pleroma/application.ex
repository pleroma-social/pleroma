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

  @type env() :: :test | :benchmark | :dev | :prod

  def name, do: @name
  def version, do: @version
  def named_version, do: @name <> " " <> @version
  def repository, do: @repository

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

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    # Scrubbers are compiled at runtime and therefore will cause a conflict
    # every time the application is restarted, so we disable module
    # conflicts at runtime
    Code.compiler_options(ignore_module_conflict: true)
    # Disable warnings_as_errors at runtime, it breaks Phoenix live reload
    # due to protocol consolidation warnings
    Code.compiler_options(warnings_as_errors: false)
    Pleroma.Telemetry.Logger.attach()
    Config.Holder.save_default()
    Pleroma.HTML.compile_scrubbers()
    Pleroma.Config.Oban.warn()
    Config.DeprecationWarnings.warn()
    Pleroma.Plugs.HTTPSecurityPlug.warn_if_disabled()
    Pleroma.Application.Requirements.verify!()
    setup_instrumenters()
    load_custom_modules()
    check_system_commands()
    Pleroma.Docs.JSON.compile()

    if Application.get_env(:tesla, :adapter) == Tesla.Adapter.Gun do
      if version = Pleroma.OTPVersion.version() do
        [major, minor] =
          version
          |> String.split(".")
          |> Enum.map(&String.to_integer/1)
          |> Enum.take(2)

        if (major == 22 and minor < 2) or major < 22 do
          raise "
            !!!OTP VERSION WARNING!!!
            You are using gun adapter with OTP version #{version}, which doesn't support correct handling of unordered certificates chains. Please update your Erlang/OTP to at least 22.2.
            "
        end
      else
        raise "
          !!!OTP VERSION WARNING!!!
          To support correct handling of unordered certificates chains - OTP version must be > 22.2.
          "
      end
    end

    # Define workers and child supervisors to be supervised
    children = [
      Pleroma.Repo,
      Pleroma.Application.DynamicSupervisor,
      {Registry, keys: :duplicate, name: Pleroma.Application.DynamicSupervisor.registry()}
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    Supervisor.start_link(children, strategy: :one_for_one, name: Pleroma.Supervisor)
  end

  def start_phase(:update_env, :normal, _args) do
    # Load and update the environment from the config settings in the database
    Pleroma.Config.Environment.load_and_update()
  end

  def start_phase(:static_children, :normal, _args) do
    # Start static children,
    # which don't require any configuration or can be configured in runtime
    Pleroma.Application.Static.start_children(@env)
  end

  def start_phase(:dynamic_children, :normal, _args) do
    # Start dynamic children,
    # which require restart after some config changes
    Pleroma.Application.DynamicSupervisor.start_children(@env)
  end

  def load_custom_modules do
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
    Pleroma.Web.Endpoint.Instrumenter.setup()
  end

  defp check_system_commands do
    filters = Config.get([Pleroma.Upload, :filters])

    check_filter = fn filter, command_required ->
      with true <- filter in filters,
           false <- Pleroma.Utils.command_available?(command_required) do
        Logger.error(
          "#{filter} is specified in list of Pleroma.Upload filters, but the #{command_required} command is not found"
        )
      end
    end

    check_filter.(Pleroma.Upload.Filters.Exiftool, "exiftool")
    check_filter.(Pleroma.Upload.Filters.Mogrify, "mogrify")
    check_filter.(Pleroma.Upload.Filters.Mogrifun, "mogrify")
  end
end
