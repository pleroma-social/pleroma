# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Pleroma do
  @apps [
    :ecto,
    :ecto_sql,
    :postgrex,
    :db_connection,
    :cachex,
    :flake_id,
    :swoosh,
    :timex,
    :fast_html
  ]

  @cachex_children ["object", "user", "scrubber", "web_resp"]

  @doc "Common functions to be reused in mix tasks"
  @spec start_pleroma() :: {:ok, pid()}
  def start_pleroma do
    Pleroma.Config.Holder.save_default()
    Pleroma.Application.limiters_setup()
    Pleroma.Config.DeprecationWarnings.check_oban_config()
    Application.put_env(:phoenix, :serve_endpoints, false, persistent: true)

    unless System.get_env("DEBUG") do
      Logger.remove_backend(:console)
    end

    adapter = Application.get_env(:tesla, :adapter)

    apps =
      if adapter == Tesla.Adapter.Gun do
        [:gun | @apps]
      else
        [:hackney | @apps]
      end

    Enum.each(apps, &Application.ensure_all_started/1)

    oban_config = [
      crontab: [],
      repo: Pleroma.Repo,
      log: false,
      queues: [],
      plugins: []
    ]

    children = [
      Pleroma.Application.ConfigDependentDeps,
      Pleroma.Repo,
      Pleroma.Emoji,
      Supervisor.child_spec({Task, &Pleroma.Application.Environment.load_from_db_and_update/0},
        id: :update_env
      ),
      {Oban, oban_config},
      {Majic.Pool,
       [name: Pleroma.MajicPool, pool_size: Pleroma.Config.get([:majic_pool, :size], 2)]},
      Pleroma.Web.Endpoint
    ]

    children = [Pleroma.Application.StartUpDependencies.adapter_module() | children]

    cachex_children =
      Enum.map(@cachex_children, &Pleroma.Application.StartUpDependencies.cachex_spec({&1, []}))

    Supervisor.start_link(children ++ cachex_children,
      strategy: :one_for_one,
      name: Pleroma.Supervisor
    )
  end

  def load_pleroma do
    Application.load(:pleroma)
  end

  def get_option(options, opt, prompt, defval \\ nil, defname \\ nil) do
    Keyword.get(options, opt) || shell_prompt(prompt, defval, defname)
  end

  def shell_prompt(prompt, defval \\ nil, defname \\ nil) do
    prompt_message = "#{prompt} [#{defname || defval}] "

    input =
      if mix_shell?(),
        do: Mix.shell().prompt(prompt_message),
        else: :io.get_line(prompt_message)

    case input do
      "\n" ->
        case defval do
          nil ->
            shell_prompt(prompt, defval, defname)

          defval ->
            defval
        end

      input ->
        String.trim(input)
    end
  end

  def shell_info(message) do
    if mix_shell?(),
      do: Mix.shell().info(message),
      else: IO.puts(message)
  end

  def shell_error(message) do
    if mix_shell?(),
      do: Mix.shell().error(message),
      else: IO.puts(:stderr, message)
  end

  @doc "Performs a safe check whether `Mix.shell/0` is available (does not raise if Mix is not loaded)"
  def mix_shell?, do: :erlang.function_exported(Mix, :shell, 0)

  def escape_sh_path(path) do
    ~S(') <> String.replace(path, ~S('), ~S(\')) <> ~S(')
  end
end
