defmodule Pleroma.Web.FrontendController do
  use Pleroma.Web, :controller

  defmacro __using__(_opts) do
    quote do
      require Logger

      def fallback(conn, _params) do
        conn
        |> put_status(404)
        |> text("Not found")
      end

      def redirector_with_preload(conn, %{"path" => ["pleroma", "admin"]}) do
        redirect(conn, to: "/pleroma/admin/")
      end

      def redirector_with_preload(conn, params) do
        index_with_generated_data(conn, params, [:preload])
      end

      def index_with_generated_data(conn, params, generators) do
        {:ok, path} = Pleroma.Frontend.file_path("index.html")
        {:ok, index_content} = File.read(path)

        generated =
          Enum.reduce(generators, "", fn generator, acc ->
            acc <> generate_data(conn, params, generator)
          end)

        response = String.replace(index_content, "<!--server-generated-meta-->", generated)

        html(conn, response)
      end

      defp generate_data(conn, params, :preload) do
        try do
          Pleroma.Web.Preload.build_tags(conn, params)
        rescue
          e ->
            Logger.error(
              "Preloading for #{conn.request_path} failed.\n" <>
                Exception.format(:error, e, __STACKTRACE__)
            )

            ""
        end
      end

      defp generate_data(conn, params, :metadata) do
        try do
          Pleroma.Web.Metadata.build_tags(params)
        rescue
          e ->
            Logger.error(
              "Metadata rendering for #{conn.request_path} failed.\n" <>
                Exception.format(:error, e, __STACKTRACE__)
            )

            ""
        end
      end

      defoverridable redirector_with_preload: 2, fallback: 2
    end
  end

  defp action(conn, _opts) do
    fe_config = conn.private[:frontend] || Pleroma.Frontend.get_config(:primary)

    action_name = action_name(conn)

    {controller, action} =
      cond do
        function_exported?(fe_config["controller"], action_name, 2) ->
          {fe_config["controller"], action_name}

        true ->
          {fe_config["controller"], :fallback}
      end

    conn
    |> put_private(:frontend, fe_config)
    |> put_view(Phoenix.Controller.__view__(controller))
    |> controller.call(controller.init(action))
  end
end
