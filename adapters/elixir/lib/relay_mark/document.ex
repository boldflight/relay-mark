defmodule RelayMark.Document do
  @moduledoc "RelayMark document AST struct."

  alias RelayMark.{Annotation, Block, Resource}

  defstruct type: "relaymark.document",
            version: 1,
            frontmatter: %{},
            blocks: [],
            annotations: [],
            resources: []

  @type t :: %__MODULE__{
          type: String.t(),
          version: pos_integer(),
          frontmatter: map(),
          blocks: [Block.t()],
          annotations: [Annotation.t()],
          resources: [Resource.t()]
        }

  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      type: Map.fetch!(map, "type"),
      version: Map.fetch!(map, "version"),
      frontmatter: Map.get(map, "frontmatter", %{}),
      blocks: Enum.map(Map.get(map, "blocks", []), &Block.from_map/1),
      annotations: Enum.map(Map.get(map, "annotations", []), &Annotation.from_map/1),
      resources: Enum.map(Map.get(map, "resources", []), &Resource.from_map/1)
    }
  end
end
