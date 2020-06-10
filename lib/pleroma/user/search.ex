# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.User.Search do
  alias Pleroma.Pagination
  alias Pleroma.User
  import Ecto.Query

  @limit 20
  @levenshtein_max_query_length 5
  @search_rank_threshold 0

  def search(query_string, opts \\ []) do
    resolve = Keyword.get(opts, :resolve, false)
    following = Keyword.get(opts, :following, false)
    result_limit = Keyword.get(opts, :limit, @limit)
    offset = Keyword.get(opts, :offset, 0)

    for_user = Keyword.get(opts, :for_user)

    query_string = format_query(query_string)

    maybe_resolve(resolve, for_user, query_string)

    results =
      query_string
      |> search_query(for_user, following)
      |> Pagination.fetch_paginated(%{"offset" => offset, "limit" => result_limit}, :offset)

    results
  end

  defp format_query(query_string) do
    # Strip the beginning @ off if there is a query
    query_string =
      query_string
      |> String.trim()
      |> String.trim_leading("@")

    with [name, domain] <- String.split(query_string, "@") do
      encoded_domain =
        domain
        |> String.replace(~r/[!-\-|@|[-`|{-~|\/|:|\s]+/, "")
        |> String.to_charlist()
        |> :idna.encode()
        |> to_string()

      name <> "@" <> encoded_domain
    else
      _ -> query_string
    end
  end

  defp levenshtein_applicable?(query_string) do
    String.length(query_string) <= @levenshtein_max_query_length
  end

  defp search_query(query_string, for_user, following) do
    query =
      for_user
      |> base_query(following)
      |> filter_blocked_user(for_user)
      |> filter_invisible_users()
      |> filter_blocked_domains(for_user)

    query =
      if levenshtein_applicable?(query_string) do
        query
        |> levenshtein_distance(query_string)
        |> fts_levenshtein_search(query_string)
        |> trigram_levenshtein_rank(query_string)
      else
        query
        |> fts_search(query_string)
        |> trigram_rank(query_string)
      end

    query
    |> boost_search_rank(for_user)
    |> filter_by_search_rank()
    |> subquery()
    |> order_by(desc: :search_rank)
    |> maybe_restrict_local(for_user)
  end

  defp fts_search(query, query_string) do
    query_string = to_tsquery(query_string)

    from(
      u in query,
      where:
        fragment(
          """
          (to_tsvector('simple', ?) || to_tsvector('simple', ?)) @@ to_tsquery('simple', ?)
          """,
          u.name,
          u.nickname,
          ^query_string
        )
    )
  end

  defp fts_levenshtein_search(query, query_string) do
    tsquery = to_tsquery(query_string)

    from(
      u in subquery(query),
      where:
        fragment(
          """
          ? <= 2 OR
            (to_tsvector('simple', ?) || to_tsvector('simple', ?)) @@ to_tsquery('simple', ?)
          """,
          u.levenshtein_distance,
          u.name,
          u.nickname,
          ^tsquery
        )
    )
  end

  defp to_tsquery(query_string) do
    String.trim_trailing(query_string, "@" <> local_domain())
    |> String.replace(~r/[!-\/|@|[-`|{-~|:-?]+/, " ")
    |> String.trim()
    |> String.split()
    |> Enum.map(&(&1 <> ":*"))
    |> Enum.join(" | ")
  end

  # Trigram-based rank with bonus for close Levenshtein distance b/w query and nickname
  defp trigram_levenshtein_rank(query, query_string) do
    from(
      u in subquery(query),
      select_merge: %{
        search_rank:
          fragment(
            "similarity(?, trim(? || ' ' || coalesce(?, ''))) + \
                            (CASE WHEN ? = 0 THEN 1.0 \
                              WHEN ? = 1 AND length(?) > 1 THEN 0.5
                              WHEN ? = 2 AND length(?) > 3 THEN 0.2
                              ELSE 0 END)",
            ^query_string,
            u.nickname,
            u.name,
            u.levenshtein_distance,
            u.levenshtein_distance,
            ^query_string,
            u.levenshtein_distance,
            ^query_string
          )
      }
    )
  end

  defp levenshtein_distance(query, query_string) do
    from(
      u in query,
      select_merge: %{
        levenshtein_distance:
          fragment(
            "levenshtein(?, regexp_replace(?, '@.+', ''))",
            ^query_string,
            u.nickname
          )
      }
    )
  end

  defp trigram_rank(query, query_string) do
    from(
      u in query,
      select_merge: %{
        search_rank:
          fragment(
            "similarity(?, trim(? || ' ' || coalesce(?, '')))",
            ^query_string,
            u.nickname,
            u.name
          )
      }
    )
  end

  defp base_query(_user, false), do: User
  defp base_query(user, true), do: User.get_followers_query(user)

  defp filter_invisible_users(query) do
    from(q in query, where: q.invisible == false)
  end

  defp filter_blocked_user(query, %User{} = blocker) do
    query
    |> join(:left, [u], b in Pleroma.UserRelationship,
      as: :blocks,
      on: b.relationship_type == ^:block and b.source_id == ^blocker.id and u.id == b.target_id
    )
    |> where([blocks: b], is_nil(b.target_id))
  end

  defp filter_blocked_user(query, _), do: query

  defp filter_blocked_domains(query, %User{domain_blocks: domain_blocks})
       when length(domain_blocks) > 0 do
    domains = Enum.join(domain_blocks, ",")

    from(
      q in query,
      where: fragment("substring(ap_id from '.*://([^/]*)') NOT IN (?)", ^domains)
    )
  end

  defp filter_blocked_domains(query, _), do: query

  defp maybe_resolve(true, user, query) do
    case {limit(), user} do
      {:all, _} -> :noop
      {:unauthenticated, %User{}} -> User.get_or_fetch(query)
      {:unauthenticated, _} -> :noop
      {false, _} -> User.get_or_fetch(query)
    end
  end

  defp maybe_resolve(_, _, _), do: :noop

  defp maybe_restrict_local(q, user) do
    case {limit(), user} do
      {:all, _} -> restrict_local(q)
      {:unauthenticated, %User{}} -> q
      {:unauthenticated, _} -> restrict_local(q)
      {false, _} -> q
    end
  end

  defp limit, do: Pleroma.Config.get([:instance, :limit_to_local_content], :unauthenticated)

  defp restrict_local(q), do: where(q, [u], u.local == true)

  defp local_domain, do: Pleroma.Config.get([Pleroma.Web.Endpoint, :url, :host])

  defp boost_search_rank(query, %User{} = for_user) do
    friends_ids = User.get_friends_ids(for_user)
    followers_ids = User.get_followers_ids(for_user)

    from(u in subquery(query),
      select_merge: %{
        search_rank:
          fragment(
            """
             CASE WHEN (?) THEN (?) * 1.5
             WHEN (?) THEN (?) * 1.3
             WHEN (?) THEN (?) * 1.1
             ELSE (?) END
            """,
            u.id in ^friends_ids and u.id in ^followers_ids,
            u.search_rank,
            u.id in ^friends_ids,
            u.search_rank,
            u.id in ^followers_ids,
            u.search_rank,
            u.search_rank
          )
      }
    )
  end

  defp boost_search_rank(query, _for_user), do: query

  defp filter_by_search_rank(query) do
    from(u in subquery(query), where: u.search_rank > @search_rank_threshold)
  end
end
