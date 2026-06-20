defmodule RelayMark.Annotation do
  @moduledoc "RelayMark annotation struct."

  alias RelayMark.Inline

  defstruct id: nil,
            type: nil,
            anchor: %{},
            props: %{},
            content: []

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          anchor: map(),
          props: map(),
          content: [Inline.t()]
        }

  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      id: Map.fetch!(map, "id"),
      type: Map.fetch!(map, "type"),
      anchor: Map.fetch!(map, "anchor"),
      props: Map.get(map, "props", %{}),
      content: Enum.map(Map.get(map, "content", []), &Inline.from_map/1)
    }
  end
end
