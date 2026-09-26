defmodule RelayMark.Inline do
  @moduledoc "RelayMark inline node struct."

  @commonmark_inline_types ~w(text hard_break soft_break link emphasis strong strikethrough code_span underline highlight superscript subscript)
  @block_reference_types ~w(relay.evidence_ref relay.file_ref relay.note_ref relay.url_ref)

  defstruct type: nil,
            text: nil,
            id: nil,
            label: nil,
            href: nil,
            props: %{},
            content: []

  @type t :: %__MODULE__{
          type: String.t(),
          text: String.t() | nil,
          id: String.t() | nil,
          label: String.t() | nil,
          href: String.t() | nil,
          props: map(),
          content: [t()]
        }

  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      type: Map.fetch!(map, "type"),
      text: Map.get(map, "text"),
      id: Map.get(map, "id"),
      label: Map.get(map, "label"),
      href: Map.get(map, "href"),
      props: Map.get(map, "props", %{}),
      content: Enum.map(Map.get(map, "content", []), &from_map/1)
    }
  end

  @doc false
  @spec inline_type?(String.t()) :: boolean()
  def inline_type?(type) when type in @commonmark_inline_types, do: true
  def inline_type?(type) when type in @block_reference_types, do: false

  def inline_type?("relay." <> type) do
    String.ends_with?(type, "_ref")
  end

  def inline_type?(_type), do: false
end
