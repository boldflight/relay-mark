defmodule RelayMark.JSON do
  @moduledoc false

  @spec decode(binary()) :: {:ok, term()} | {:error, term()}
  def decode(json) when is_binary(json) do
    json = String.trim(json)

    with {:ok, value, rest} <- parse_value(json),
         "" <- String.trim_leading(rest) do
      {:ok, value}
    else
      {:error, _} = error -> error
      rest when is_binary(rest) -> {:error, {:unexpected_trailing_json, rest}}
    end
  end

  defp parse_value(json) do
    json = String.trim_leading(json)

    cond do
      String.starts_with?(json, "{") -> parse_object(binary_part(json, 1, byte_size(json) - 1), %{})
      String.starts_with?(json, "[") -> parse_array(binary_part(json, 1, byte_size(json) - 1), [])
      String.starts_with?(json, "\"") -> parse_string(binary_part(json, 1, byte_size(json) - 1), "")
      String.starts_with?(json, "true") -> {:ok, true, binary_part(json, 4, byte_size(json) - 4)}
      String.starts_with?(json, "false") -> {:ok, false, binary_part(json, 5, byte_size(json) - 5)}
      String.starts_with?(json, "null") -> {:ok, nil, binary_part(json, 4, byte_size(json) - 4)}
      true -> parse_number(json)
    end
  end

  defp parse_object(json, acc) do
    json = String.trim_leading(json)

    cond do
      String.starts_with?(json, "}") ->
        {:ok, acc, binary_part(json, 1, byte_size(json) - 1)}

      true ->
        with {:ok, key, rest} <- parse_value(json),
             rest <- String.trim_leading(rest),
             true <- String.starts_with?(rest, ":"),
             {:ok, value, rest} <- parse_value(binary_part(rest, 1, byte_size(rest) - 1)) do
          rest = String.trim_leading(rest)
          acc = Map.put(acc, key, value)

          cond do
            String.starts_with?(rest, ",") ->
              parse_object(binary_part(rest, 1, byte_size(rest) - 1), acc)

            String.starts_with?(rest, "}") ->
              {:ok, acc, binary_part(rest, 1, byte_size(rest) - 1)}

            true ->
              {:error, {:invalid_object, rest}}
          end
        else
          false -> {:error, {:expected_colon, json}}
          {:error, _} = error -> error
        end
    end
  end

  defp parse_array(json, acc) do
    json = String.trim_leading(json)

    cond do
      String.starts_with?(json, "]") ->
        {:ok, Enum.reverse(acc), binary_part(json, 1, byte_size(json) - 1)}

      true ->
        with {:ok, value, rest} <- parse_value(json) do
          rest = String.trim_leading(rest)

          cond do
            String.starts_with?(rest, ",") ->
              parse_array(binary_part(rest, 1, byte_size(rest) - 1), [value | acc])

            String.starts_with?(rest, "]") ->
              {:ok, Enum.reverse([value | acc]), binary_part(rest, 1, byte_size(rest) - 1)}

            true ->
              {:error, {:invalid_array, rest}}
          end
        end
    end
  end

  defp parse_string(<<"\"", rest::binary>>, acc), do: {:ok, acc, rest}
  defp parse_string(<<"\\\"", rest::binary>>, acc), do: parse_string(rest, acc <> "\"")
  defp parse_string(<<"\\\\", rest::binary>>, acc), do: parse_string(rest, acc <> "\\")
  defp parse_string(<<"\\/", rest::binary>>, acc), do: parse_string(rest, acc <> "/")
  defp parse_string(<<"\\b", rest::binary>>, acc), do: parse_string(rest, acc <> <<8>>)
  defp parse_string(<<"\\f", rest::binary>>, acc), do: parse_string(rest, acc <> <<12>>)
  defp parse_string(<<"\\n", rest::binary>>, acc), do: parse_string(rest, acc <> "\n")
  defp parse_string(<<"\\r", rest::binary>>, acc), do: parse_string(rest, acc <> "\r")
  defp parse_string(<<"\\t", rest::binary>>, acc), do: parse_string(rest, acc <> "\t")

  defp parse_string(<<"\\u", hex::binary-size(4), rest::binary>>, acc) do
    case Integer.parse(hex, 16) do
      {codepoint, ""} -> parse_string(rest, acc <> <<codepoint::utf8>>)
      _ -> {:error, {:invalid_unicode_escape, hex}}
    end
  end

  defp parse_string(<<char::utf8, rest::binary>>, acc), do: parse_string(rest, acc <> <<char::utf8>>)
  defp parse_string("", _acc), do: {:error, :unterminated_string}

  defp parse_number(json) do
    case Regex.run(~r/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/, json) do
      [number] ->
        rest = binary_part(json, byte_size(number), byte_size(json) - byte_size(number))

        value =
          if String.contains?(number, [".", "e", "E"]) do
            String.to_float(number)
          else
            String.to_integer(number)
          end

        {:ok, value, rest}

      _ ->
        {:error, {:invalid_json, json}}
    end
  end
end
