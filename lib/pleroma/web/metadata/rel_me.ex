# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Metadata.Providers.RelMe do
  alias Pleroma.Web.Metadata.Providers.Provider
  @behaviour Provider

  @impl Provider
  def build_tags(%{user: %{bio: bio}}) when is_binary(bio) do
    bio_tree = Floki.parse_fragment!(bio)

    (Floki.attribute(bio_tree, "link[rel~=me]", "href") ++
       Floki.attribute(bio_tree, "a[rel~=me]", "href"))
    |> Enum.map(fn link ->
      {:link, [rel: "me", href: link], []}
    end)
  end

  def build_tags(_), do: []
end
