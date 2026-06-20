defmodule RelayMark.Manifest do
  @moduledoc "RelayMark projection manifest struct."

  defstruct type: "relaymark.manifest",
            version: 1,
            actions: [],
            mentions: [],
            forms: [],
            sources: [],
            diagnostics: []

  @type t :: %__MODULE__{
          type: String.t(),
          version: pos_integer(),
          actions: [RelayMark.Manifest.Action.t()],
          mentions: [RelayMark.Manifest.Mention.t()],
          forms: [RelayMark.Manifest.FormQuestion.t()],
          sources: [RelayMark.Manifest.Source.t()],
          diagnostics: [map()]
        }

  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      type: Map.fetch!(map, "type"),
      version: Map.fetch!(map, "version"),
      actions: Enum.map(Map.get(map, "actions", []), &RelayMark.Manifest.Action.from_map/1),
      mentions: Enum.map(Map.get(map, "mentions", []), &RelayMark.Manifest.Mention.from_map/1),
      forms: Enum.map(Map.get(map, "forms", []), &RelayMark.Manifest.FormQuestion.from_map/1),
      sources: Enum.map(Map.get(map, "sources", []), &RelayMark.Manifest.Source.from_map/1),
      diagnostics: Map.get(map, "diagnostics", [])
    }
  end
end

defmodule RelayMark.Manifest.Action do
  @moduledoc "Reviewable action projection."

  defstruct block_id: nil,
            action: nil,
            args: %{},
            target: nil,
            destination: nil,
            visibility: nil,
            review: nil,
            evidence_refs: []

  @type t :: %__MODULE__{
          block_id: String.t(),
          action: String.t(),
          args: map(),
          target: String.t() | nil,
          destination: String.t() | nil,
          visibility: String.t() | nil,
          review: String.t(),
          evidence_refs: [String.t()]
        }

  def from_map(map) do
    %__MODULE__{
      block_id: Map.fetch!(map, "block_id"),
      action: Map.fetch!(map, "action"),
      args: Map.get(map, "args", %{}),
      target: Map.get(map, "target"),
      destination: Map.get(map, "destination"),
      visibility: Map.get(map, "visibility"),
      review: Map.fetch!(map, "review"),
      evidence_refs: Map.get(map, "evidence_refs", [])
    }
  end
end

defmodule RelayMark.Manifest.Mention do
  @moduledoc "Mention projection."

  defstruct block_id: nil,
            kind: nil,
            id: nil,
            label: nil

  @type t :: %__MODULE__{
          block_id: String.t(),
          kind: String.t(),
          id: String.t() | nil,
          label: String.t()
        }

  def from_map(map) do
    %__MODULE__{
      block_id: Map.fetch!(map, "block_id"),
      kind: Map.fetch!(map, "kind"),
      id: Map.get(map, "id"),
      label: Map.fetch!(map, "label")
    }
  end
end

defmodule RelayMark.Manifest.FormQuestion do
  @moduledoc "Form question projection."

  defstruct block_id: nil,
            key: nil,
            label: nil,
            field_type: nil,
            required: false,
            options: []

  @type t :: %__MODULE__{
          block_id: String.t(),
          key: String.t(),
          label: String.t(),
          field_type: String.t(),
          required: boolean(),
          options: [String.t()]
        }

  def from_map(map) do
    %__MODULE__{
      block_id: Map.fetch!(map, "block_id"),
      key: Map.fetch!(map, "key"),
      label: Map.fetch!(map, "label"),
      field_type: Map.fetch!(map, "field_type"),
      required: Map.get(map, "required", false),
      options: Map.get(map, "options", [])
    }
  end
end

defmodule RelayMark.Manifest.Source do
  @moduledoc "Source projection."

  defstruct block_id: nil,
            kind: nil,
            source_id: nil,
            start: nil,
            end: nil,
            uri: nil,
            label: nil

  @type t :: %__MODULE__{
          block_id: String.t(),
          kind: String.t(),
          source_id: String.t() | nil,
          start: String.t() | nil,
          end: String.t() | nil,
          uri: String.t() | nil,
          label: String.t() | nil
        }

  def from_map(map) do
    %__MODULE__{
      block_id: Map.fetch!(map, "block_id"),
      kind: Map.fetch!(map, "kind"),
      source_id: Map.get(map, "source_id"),
      start: Map.get(map, "start"),
      end: Map.get(map, "end"),
      uri: Map.get(map, "uri"),
      label: Map.get(map, "label")
    }
  end
end
