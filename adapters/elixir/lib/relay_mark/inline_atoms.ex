defmodule RelayMark.InlineAtoms do
  @moduledoc "Canonical inline reference source escaping. Resolution remains host-owned."
  @type_pattern ~r/\A[A-Z][A-Za-z0-9]*(?: [A-Z][A-Za-z0-9]*)*\z/u
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/u
  @quoted ~r/[\r\n\[\]"\\`*_<>!]/u
  def reference_source(type, id, label)
      when is_binary(type) and is_binary(id) and is_binary(label) do
    if type != "Tag" and Regex.match?(@type_pattern, type) and Regex.match?(@uuid, id) and
         label != "" and String.valid?(label) do
      encoded =
        if label != String.trim(label) or Regex.match?(@quoted, label) do
          bytes = :unicode.characters_to_binary(label, :utf8, {:utf16, :big})

          "\"" <>
            Enum.map_join(for(<<unit::16 <- bytes>>, do: unit), fn unit ->
              "\\u" <>
                String.pad_leading(Integer.to_string(unit, 16) |> String.downcase(), 4, "0")
            end) <> "\""
        else
          label
        end

      {:ok, "[[#{type}: #{id} | #{encoded}]]"}
    else
      :error
    end
  end

  def reference_source(_, _, _), do: :error

  def parse_reference_source(source) when is_binary(source) do
    with [_, type, id, raw] <- Regex.run(~r/\A\[\[([^:]+): ([^ ]+) \| ([\s\S]+)\]\]\z/u, source),
         {:ok, label} <- decode_label(raw),
         {:ok, ^source} <- reference_source(type, id, label) do
      {:ok,
       %{
         "type" => "relay.entity_ref",
         "id" => id,
         "label" => label,
         "props" => %{"entityType" => type, "source" => source}
       }}
    else
      _ -> :error
    end
  end

  def parse_reference_source(_), do: :error
  defp decode_label("\"" <> _ = raw), do: Jason.decode(raw)
  defp decode_label(raw), do: {:ok, raw}
end
