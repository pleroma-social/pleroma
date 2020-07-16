# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Config.Converter do
  @moduledoc """
  Converts json structures with strings into elixir structures and types and vice versa.
  """
  @spec to_elixir_types(boolean() | String.t() | map() | list()) :: term()
  def to_elixir_types(%{"tuple" => [":args", args]}) when is_list(args) do
    arguments =
      Enum.map(args, fn arg ->
        if String.contains?(arg, ["{", "}"]) do
          {elem, []} = Code.eval_string(arg)
          elem
        else
          to_elixir_types(arg)
        end
      end)

    {:args, arguments}
  end

  def to_elixir_types(%{"tuple" => [":proxy_url", %{"tuple" => [type, host, port]}]}) do
    {:proxy_url, {string_to_elixir_types(type), parse_host(host), port}}
  end

  def to_elixir_types(%{"tuple" => [":partial_chain", entity]}) do
    {partial_chain, []} =
      entity
      |> String.replace(~r/[^\w|^{:,[|^,|^[|^\]^}|^\/|^\.|^"]^\s/, "")
      |> Code.eval_string()

    {:partial_chain, partial_chain}
  end

  def to_elixir_types(%{"tuple" => entity}) do
    Enum.reduce(entity, {}, &Tuple.append(&2, to_elixir_types(&1)))
  end

  def to_elixir_types(entity) when is_map(entity) do
    Map.new(entity, fn {k, v} -> {to_elixir_types(k), to_elixir_types(v)} end)
  end

  def to_elixir_types(entity) when is_list(entity) do
    Enum.map(entity, &to_elixir_types/1)
  end

  def to_elixir_types(entity) when is_binary(entity) do
    entity
    |> String.trim()
    |> string_to_elixir_types()
  end

  def to_elixir_types(entity), do: entity

  defp parse_host("localhost"), do: :localhost

  defp parse_host(host) do
    charlist = to_charlist(host)

    case :inet.parse_address(charlist) do
      {:error, :einval} ->
        charlist

      {:ok, ip} ->
        ip
    end
  end

  @spec string_to_elixir_types(String.t()) ::
          atom() | Regex.t() | module() | String.t() | no_return()
  def string_to_elixir_types("~r" <> _pattern = regex) do
    pattern =
      ~r/^~r(?'delimiter'[\/|"'([{<]{1})(?'pattern'.+)[\/|"')\]}>]{1}(?'modifier'[uismxfU]*)/u

    delimiters = ["/", "|", "\"", "'", {"(", ")"}, {"[", "]"}, {"{", "}"}, {"<", ">"}]

    with %{"modifier" => modifier, "pattern" => pattern, "delimiter" => regex_delimiter} <-
           Regex.named_captures(pattern, regex),
         {:ok, {leading, closing}} <- find_valid_delimiter(delimiters, pattern, regex_delimiter),
         {result, _} <- Code.eval_string("~r#{leading}#{pattern}#{closing}#{modifier}") do
      result
    end
  end

  def string_to_elixir_types(":" <> atom), do: String.to_atom(atom)

  def string_to_elixir_types(value) do
    if module_name?(value) do
      String.to_existing_atom("Elixir." <> value)
    else
      value
    end
  end

  defp find_valid_delimiter([], _string, _) do
    raise(ArgumentError, message: "valid delimiter for Regex expression not found")
  end

  defp find_valid_delimiter([{leading, closing} = delimiter | others], pattern, regex_delimiter)
       when is_tuple(delimiter) do
    if String.contains?(pattern, closing) do
      find_valid_delimiter(others, pattern, regex_delimiter)
    else
      {:ok, {leading, closing}}
    end
  end

  defp find_valid_delimiter([delimiter | others], pattern, regex_delimiter) do
    if String.contains?(pattern, delimiter) do
      find_valid_delimiter(others, pattern, regex_delimiter)
    else
      {:ok, {delimiter, delimiter}}
    end
  end

  @spec module_name?(String.t()) :: boolean()
  def module_name?(string) do
    Regex.match?(~r/^(Pleroma|Phoenix|Tesla|Quack|Ueberauth|Swoosh)\./, string) or
      string in ["Oban", "Ueberauth", "ExSyslogger"]
  end

  @spec to_json_types(term()) :: map() | list() | boolean() | String.t() | integer()
  def to_json_types(entity) when is_list(entity) do
    Enum.map(entity, &to_json_types/1)
  end

  def to_json_types(%Regex{} = entity), do: inspect(entity)

  def to_json_types(entity) when is_map(entity) do
    Map.new(entity, fn {k, v} -> {to_json_types(k), to_json_types(v)} end)
  end

  def to_json_types({:args, args}) when is_list(args) do
    arguments =
      Enum.map(args, fn
        arg when is_tuple(arg) -> inspect(arg)
        arg -> to_json_types(arg)
      end)

    %{"tuple" => [":args", arguments]}
  end

  def to_json_types({:proxy_url, {type, :localhost, port}}) do
    %{"tuple" => [":proxy_url", %{"tuple" => [to_json_types(type), "localhost", port]}]}
  end

  def to_json_types({:proxy_url, {type, host, port}}) when is_tuple(host) do
    ip =
      host
      |> :inet_parse.ntoa()
      |> to_string()

    %{
      "tuple" => [
        ":proxy_url",
        %{"tuple" => [to_json_types(type), ip, port]}
      ]
    }
  end

  def to_json_types({:proxy_url, {type, host, port}}) do
    %{
      "tuple" => [
        ":proxy_url",
        %{"tuple" => [to_json_types(type), to_string(host), port]}
      ]
    }
  end

  def to_json_types({:partial_chain, entity}),
    do: %{"tuple" => [":partial_chain", inspect(entity)]}

  def to_json_types(entity) when is_tuple(entity) do
    value =
      entity
      |> Tuple.to_list()
      |> to_json_types()

    %{"tuple" => value}
  end

  def to_json_types(entity) when is_binary(entity), do: entity

  def to_json_types(entity) when is_boolean(entity) or is_number(entity) or is_nil(entity) do
    entity
  end

  def to_json_types(entity) when entity in [:"tlsv1.1", :"tlsv1.2", :"tlsv1.3"] do
    ":#{entity}"
  end

  def to_json_types(entity) when is_atom(entity), do: inspect(entity)
end
