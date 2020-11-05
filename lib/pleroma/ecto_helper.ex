# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.EctoHelper do
  @moduledoc false

  @spec pretty_errors(map(), map()) :: map()
  def pretty_errors(errors, mapping_fields \\ %{}) do
    Enum.reduce(errors, %{}, fn {field, _} = error, acc ->
      field_errors = Map.get(acc, field, []) ++ [do_prettify(error, mapping_fields)]
      Map.merge(acc, %{field => field_errors})
    end)
  end

  defp field_name(field_name, mapping_fields) do
    Map.get(mapping_fields, field_name, Phoenix.Naming.humanize(field_name))
  end

  defp do_prettify({field_name, msg}, mapping_fields) when is_binary(msg) do
    field_name(field_name, mapping_fields) <> " " <> msg
  end

  defp do_prettify({field_name, {msg, variables}}, mapping_fields) do
    compound_message = do_interpolate(msg, variables)
    do_prettify({field_name, compound_message}, mapping_fields)
  end

  defp do_interpolate(string, [{name, value} | rest]) do
    n = Atom.to_string(name)
    msg = String.replace(string, "%{#{n}}", do_to_string(value))
    do_interpolate(msg, rest)
  end

  defp do_interpolate(string, []), do: string

  defp do_to_string(value) when is_integer(value), do: Integer.to_string(value)
  defp do_to_string(value) when is_bitstring(value), do: value
  defp do_to_string(value) when is_atom(value), do: Atom.to_string(value)
end
