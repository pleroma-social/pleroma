defmodule Pleroma.Web.MediaProxy.Invalidation.Mock do
  @moduledoc false

  @behaviour Pleroma.Web.MediaProxy.Invalidation

  @impl Pleroma.Web.MediaProxy.Invalidation
  def purge(urls, _opts) do
    {:ok, urls}
  end
end
