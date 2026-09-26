defmodule RelayMark.PaperControlV3 do
  @moduledoc "Bounded authored Paper control contract; host interactions stay outside the AST."

  @fields %{
    "button" => ["label", "kind", "target"],
    "anchor" => ["name"],
    "connection" => ["provider"]
  }
  @names %{"button" => "Button", "anchor" => "Anchor", "connection" => "Connection"}
  @anchor ~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/u
  @provider ~r/\A[a-z][a-z0-9_-]*\z/u
  @command ~r/\A\/[a-z][a-z0-9._-]*(?: [^\x00-\x1f\x7f]+)?\z/u

  def canonical_source(%{"control" => control} = props) do
    with fields when is_list(fields) <- @fields[control],
         true <- Enum.sort(Map.keys(props)) == Enum.sort(["control" | fields]),
         true <- Enum.all?(fields, &is_binary(props[&1])),
         true <- valid?(control, props) do
      source = "@#{@names[control]}(" <>
         Enum.map_join(fields, ", ", fn field -> "#{field}: #{Jason.encode!(props[field])}" end) <>
         ")"

      utf16_size = source |> :unicode.characters_to_binary(:utf8, {:utf16, :little}) |> byte_size()
      if utf16_size <= 32_768, do: {:ok, source}, else: :error
    else
      _ -> :error
    end
  end

  def canonical_source(_), do: :error

  def valid_block?(%{"props" => props, "content" => []}) do
    with source when is_binary(source) <- props["source"],
         {:ok, ^source} <- canonical_source(Map.delete(props, "source")) do
      true
    else
      _ -> false
    end
  end

  def valid_block?(_), do: false

  defp valid?("button", props) do
    String.trim(props["label"]) != "" and
      case props["kind"] do
        "anchor" -> Regex.match?(@anchor, props["target"])
        "command" -> Regex.match?(@command, props["target"])
        "link" -> safe_link?(props["target"])
        _ -> false
      end
  end

  defp valid?("anchor", props), do: Regex.match?(@anchor, props["name"])
  defp valid?("connection", props), do: Regex.match?(@provider, props["provider"])

  defp safe_link?(value) do
    not Regex.match?(~r/[\s\x00-\x1f\x7f\\]/u, value) and
      (Regex.match?(~r/\A\/(?!\/)/u, value) or
         Regex.match?(~r/\Ahttps?:\/\/[^\/?#]+/iu, value) or
         Regex.match?(~r/\Amailto:[^?]+/iu, value))
  end
end
