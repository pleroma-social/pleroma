defmodule Pleroma.HTTP.Middleware.FollowRedirects do
  @moduledoc """
  Follow 3xx redirects
  ## Example
  ```
  defmodule MyClient do
    use Tesla
    plug Tesla.Middleware.FollowRedirects, max_redirects: 3 # defaults to 5
  end
  ```
  ## Options
  - `:max_redirects` - limit number of redirects (default: `5`)
  """

  @behaviour Tesla.Middleware

  @max_redirects 5
  @redirect_statuses [301, 302, 303, 307, 308]

  @impl Tesla.Middleware
  def call(env, next, opts \\ []) do
    max = Keyword.get(opts, :max_redirects, @max_redirects)

    redirect(env, next, max)
  end

  defp redirect(env, next, left) do
    opts = env.opts[:adapter]

    adapter_opts =
      if opts[:reuse_conn] do
        checkin_conn(env.url, opts)
      else
        opts
      end

    env = %{env | opts: Keyword.put(env.opts, :adapter, adapter_opts)}

    case Tesla.run(env, next) do
      {:ok, %{status: status} = res} when status in @redirect_statuses and left > 0 ->
        checkout_conn(adapter_opts)

        case Tesla.get_header(res, "location") do
          nil ->
            {:ok, res}

          location ->
            location = parse_location(location, res)

            env
            |> new_request(res.status, location)
            |> redirect(next, left - 1)
        end

      {:ok, %{status: status}} when status in @redirect_statuses ->
        checkout_conn(adapter_opts)
        {:error, {__MODULE__, :too_many_redirects}}

      other ->
        unless adapter_opts[:body_as] == :chunks do
          checkout_conn(adapter_opts)
        end

        other
    end
  end

  defp checkin_conn(url, opts) do
    uri = URI.parse(url)

    case Pleroma.Pool.Connections.checkin(uri, :gun_connections, opts) do
      nil ->
        opts

      conn when is_pid(conn) ->
        Keyword.merge(opts, conn: conn, close_conn: false)
    end
  end

  defp checkout_conn(opts) do
    if is_pid(opts[:conn]) do
      Pleroma.Pool.Connections.checkout(opts[:conn], self(), :gun_connections)
    end
  end

  # The 303 (See Other) redirect was added in HTTP/1.1 to indicate that the originally
  # requested resource is not available, however a related resource (or another redirect)
  # available via GET is available at the specified location.
  # https://tools.ietf.org/html/rfc7231#section-6.4.4
  defp new_request(env, 303, location), do: %{env | url: location, method: :get, query: []}

  # The 307 (Temporary Redirect) status code indicates that the target
  # resource resides temporarily under a different URI and the user agent
  # MUST NOT change the request method (...)
  # https://tools.ietf.org/html/rfc7231#section-6.4.7
  defp new_request(env, 307, location), do: %{env | url: location}

  defp new_request(env, _, location), do: %{env | url: location, query: []}

  defp parse_location("https://" <> _rest = location, _env), do: location
  defp parse_location("http://" <> _rest = location, _env), do: location

  defp parse_location(location, env) do
    env.url
    |> URI.parse()
    |> URI.merge(location)
    |> URI.to_string()
  end
end
