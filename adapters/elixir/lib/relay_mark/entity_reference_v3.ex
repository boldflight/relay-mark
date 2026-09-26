defmodule RelayMark.EntityReferenceV3 do
  @moduledoc """
  Strict authored source parser for the optional v3 EntityRef atom.

  This parses portable source and identity only. Entity resolution and access
  remain host-owned; this module does not admit a live collaboration profile.
  """

  @source ~r/\A@EntityRef\s*\(([\s\S]*?)\)\s*\{(?:\r\n|\n|\r)  ([^\r\n{}]+)(?:\r\n|\n|\r)\}\z/u
  @attribute ~r/\A([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*("(?:\\.|[^"\\])*")/u
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/u

  @spec parse_source(binary()) :: {:ok, map()} | :error
  def parse_source(source) when is_binary(source) and byte_size(source) <= 16_384 do
    with [_, header, body] <- Regex.run(@source, source),
         {:ok, attrs} <- parse_attributes(String.trim(header), %{}),
         "entity:" <> entity_id <- Map.get(attrs, "id"),
         true <- Regex.match?(@uuid, entity_id),
         true <- plain_body?(body),
         projection = Map.get(attrs, "projection", "link"),
         true <- projection in ["link", "chip", "card"],
         label = Map.get(attrs, "label") || body,
         true <-
           is_binary(label) and label != "" and label == String.trim(label) and
             not String.contains?(label, ["\r", "\n"]) do
      {:ok,
       %{
         "id" => attrs["id"],
         "entityId" => entity_id,
         "label" => label,
         "projection" => projection,
         "body" => body,
         "source" => source
       }}
    else
      _ -> :error
    end
  end

  def parse_source(_), do: :error

  defp parse_attributes("", attrs), do: {:ok, attrs}

  defp parse_attributes(rest, attrs) do
    with [matched, key, json] <- Regex.run(@attribute, rest),
         true <- key in ["id", "label", "projection"] and not Map.has_key?(attrs, key),
         {:ok, value} when is_binary(value) <- Jason.decode(json),
         remainder <-
           rest
           |> binary_part(byte_size(matched), byte_size(rest) - byte_size(matched))
           |> String.trim_leading() do
      cond do
        remainder == "" ->
          {:ok, Map.put(attrs, key, value)}

        String.starts_with?(remainder, ",") ->
          tail = remainder |> binary_part(1, byte_size(remainder) - 1) |> String.trim_leading()
          if tail == "", do: :error, else: parse_attributes(tail, Map.put(attrs, key, value))

        true ->
          :error
      end
    else
      _ -> :error
    end
  end

  defp plain_body?(body) do
    body == String.trim(body) and not String.contains?(body, ["[[", "]]", "](relay:"]) and
      not String.starts_with?(body, ["@", "#"])
  end
end
