defmodule RelayMark.AgentSuggestionV3 do
  @moduledoc "Authored-only v3 AgentSuggestion atom; proposal review and actions belong to hosts."

  @block_id ~r/\Ab[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}\z/u
  @reviews ["draft", "ready"]
  @kinds ["note", "action", "match", "journey", "source", "share"]
  @keys ["relaymarkId", "review", "kind", "confidence", "evidence", "content"]
  @control ~r/[\x00-\x1f\x7f]/u

  @spec to_block(map()) :: {:ok, map()} | :error
  def to_block(attrs) when is_map(attrs) do
    with true <- Enum.sort(Map.keys(attrs)) == Enum.sort(@keys),
         id when is_binary(id) <- attrs["relaymarkId"],
         true <- Regex.match?(@block_id, id),
         true <- valid_authored?(attrs) do
      props = %{
        "review" => attrs["review"],
        "kind" => attrs["kind"],
        "evidence" => attrs["evidence"]
      }

      props =
        if is_nil(attrs["confidence"]),
          do: props,
          else: Map.put(props, "confidence", attrs["confidence"])

      {:ok,
       %{
         "id" => id,
         "type" => "relay.agent_suggestion",
         "props" => props,
         "content" => [%{"type" => "text", "text" => attrs["content"]}]
       }}
    else
      _ -> :error
    end
  end

  def to_block(_), do: :error

  @spec valid_block?(map()) :: boolean()
  def valid_block?(
        %{
          "id" => id,
          "type" => "relay.agent_suggestion",
          "props" => props,
          "content" => [%{"type" => "text", "text" => content} = text_block]
        } = block
      )
      when is_map(props) and is_binary(id) do
    Enum.sort(Map.keys(block)) == Enum.sort(["id", "type", "props", "content"]) and
      text_block == %{"type" => "text", "text" => content} and
      Enum.sort(Map.keys(props)) in [
        Enum.sort(["review", "kind", "evidence"]),
        Enum.sort(["review", "kind", "evidence", "confidence"])
      ] and
      (not Map.has_key?(props, "confidence") or not is_nil(props["confidence"])) and
      Regex.match?(@block_id, id) and
      match?(
        {:ok, _},
        to_block(%{
          "relaymarkId" => id,
          "review" => props["review"],
          "kind" => props["kind"],
          "confidence" => Map.get(props, "confidence"),
          "evidence" => props["evidence"],
          "content" => content
        })
      )
  end

  def valid_block?(_), do: false

  defp valid_authored?(attrs) do
    attrs["review"] in @reviews and attrs["kind"] in @kinds and
      (is_nil(attrs["confidence"]) or
         (is_number(attrs["confidence"]) and attrs["confidence"] >= 0 and attrs["confidence"] <= 1)) and
      valid_evidence?(attrs["evidence"]) and valid_content?(attrs["content"])
  end

  defp valid_evidence?(items) when is_list(items) and length(items) <= 64 do
    Enum.all?(items, fn
      id when is_binary(id) ->
        id != "" and utf16_size(id) <= 128 and not Regex.match?(@control, id)

      _ ->
        false
    end) and length(Enum.uniq(items)) == length(items)
  end

  defp valid_evidence?(_), do: false

  defp valid_content?(content) when is_binary(content) do
    content != "" and String.trim(content) == content and
      not String.contains?(content, ["\r", <<0>>]) and
      utf16_size(content) <= 32_768
  end

  defp valid_content?(_), do: false

  defp utf16_size(value) do
    byte_size(:unicode.characters_to_binary(value, :utf8, {:utf16, :little})) |> div(2)
  end
end
