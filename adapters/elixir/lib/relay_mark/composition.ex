defmodule RelayMark.Composition do
  @moduledoc """
  Generic portable values for already-authorized linear paper composition.

  These values carry semantic roles, stable anchors, placement, and safe
  fallback policy. They intentionally contain no Relay grants, principals,
  visibility decisions, or resolved private values.
  """

  alias RelayMark.Composition.{Anchor, Item, Layer, Placement}

  defstruct type: "relaymark.layer_composition", version: 1, layers: []

  @type role :: :authored | :source | :generated | :discussion | :ink
  @type t :: %__MODULE__{type: String.t(), version: pos_integer(), layers: [Layer.t()]}

  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      type: Map.fetch!(map, "type"),
      version: Map.fetch!(map, "version"),
      layers: Enum.map(Map.get(map, "layers", []), &Layer.from_map/1)
    }
  end
end

defmodule RelayMark.Composition.Anchor do
  @moduledoc "A stable block anchor."
  defstruct [:block_id]
  @type t :: %__MODULE__{block_id: String.t()}
  def from_map(map), do: %__MODULE__{block_id: Map.fetch!(map, "block_id")}
end

defmodule RelayMark.Composition.Placement do
  @moduledoc "Deterministic placement and safe missing-anchor behavior."
  alias RelayMark.Composition.Anchor
  defstruct [:kind, :anchor, :slot, :anchor_state, :fallback]

  @type t :: %__MODULE__{
          kind: String.t(),
          anchor: Anchor.t() | nil,
          slot: String.t() | nil,
          anchor_state: String.t() | nil,
          fallback: String.t() | nil
        }
  def from_map(map) do
    %__MODULE__{
      kind: Map.fetch!(map, "kind"),
      anchor: if(map["anchor"], do: Anchor.from_map(map["anchor"])),
      slot: map["slot"],
      anchor_state: map["anchor_state"],
      fallback: map["fallback"]
    }
  end
end

defmodule RelayMark.Composition.Item do
  @moduledoc "One portable block contributed by a semantic layer."
  alias RelayMark.{Block, Composition.Placement}
  defstruct [:id, :rank, :block, :placement]

  @type t :: %__MODULE__{
          id: String.t(),
          rank: integer() | nil,
          block: Block.t(),
          placement: Placement.t() | nil
        }
  def from_map(map) do
    %__MODULE__{
      id: Map.fetch!(map, "id"),
      rank: map["rank"],
      block: map |> Map.fetch!("block") |> Block.from_map(),
      placement: if(map["placement"], do: Placement.from_map(map["placement"]))
    }
  end
end

defmodule RelayMark.Composition.Layer do
  @moduledoc "An already-authorized contribution channel with a portable semantic role."
  alias RelayMark.Composition.Item
  defstruct [:id, :role, :rank, items: []]

  @type t :: %__MODULE__{
          id: String.t(),
          role: String.t(),
          rank: integer() | nil,
          items: [Item.t()]
        }
  def from_map(map),
    do: %__MODULE__{
      id: Map.fetch!(map, "id"),
      role: Map.fetch!(map, "role"),
      rank: map["rank"],
      items: Enum.map(map["items"] || [], &Item.from_map/1)
    }
end
