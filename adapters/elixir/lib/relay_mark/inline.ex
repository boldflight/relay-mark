defmodule RelayMark.Inline do
  @moduledoc "RelayMark inline node struct."

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
end
