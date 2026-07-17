defmodule RelayMark.Manifest do
  @moduledoc "RelayMark projection manifest struct."

  defstruct type: "relaymark.manifest",
            version: 1,
            actions: [],
            mentions: [],
            references: [],
            forms: [],
            sources: [],
            claims: [],
            comparisons: [],
            diagnostics: []

  @type t :: %__MODULE__{
          type: String.t(),
          version: pos_integer(),
          actions: [RelayMark.Manifest.Action.t()],
          mentions: [RelayMark.Manifest.Mention.t()],
          references: [RelayMark.Manifest.Reference.t()],
          forms: [RelayMark.Manifest.FormQuestion.t()],
          sources: [RelayMark.Manifest.Source.t()],
          claims: [RelayMark.Manifest.Claim.t()],
          comparisons: [RelayMark.Manifest.Comparison.t()],
          diagnostics: [map()]
        }

  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      type: Map.fetch!(map, "type"),
      version: Map.fetch!(map, "version"),
      actions: Enum.map(Map.get(map, "actions", []), &RelayMark.Manifest.Action.from_map/1),
      mentions: Enum.map(Map.get(map, "mentions", []), &RelayMark.Manifest.Mention.from_map/1),
      references:
        Enum.map(Map.get(map, "references", []), &RelayMark.Manifest.Reference.from_map/1),
      forms: Enum.map(Map.get(map, "forms", []), &RelayMark.Manifest.FormQuestion.from_map/1),
      sources: Enum.map(Map.get(map, "sources", []), &RelayMark.Manifest.Source.from_map/1),
      claims: Enum.map(Map.get(map, "claims", []), &RelayMark.Manifest.Claim.from_map/1),
      comparisons:
        Enum.map(Map.get(map, "comparisons", []), &RelayMark.Manifest.Comparison.from_map/1),
      diagnostics: Map.get(map, "diagnostics", [])
    }
  end
end

defmodule RelayMark.Manifest.Reference do
  @moduledoc "Inline Relay reference projection."

  defstruct block_id: nil,
            type: nil,
            id: nil,
            label: nil,
            href: nil

  @type t :: %__MODULE__{
          block_id: String.t(),
          type: String.t(),
          id: String.t() | nil,
          label: String.t() | nil,
          href: String.t() | nil
        }

  def from_map(map) do
    %__MODULE__{
      block_id: Map.fetch!(map, "block_id"),
      type: Map.fetch!(map, "type"),
      id: Map.get(map, "id"),
      label: Map.get(map, "label"),
      href: Map.get(map, "href")
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

defmodule RelayMark.Manifest.Claim do
  @moduledoc "Evidence-backed research claim projection."

  defstruct block_id: nil,
            key: nil,
            subject: nil,
            status: nil,
            confidence: nil,
            evidence_refs: [],
            text: nil

  @type t :: %__MODULE__{
          block_id: String.t(),
          key: String.t(),
          subject: String.t() | nil,
          status: String.t(),
          confidence: number() | nil,
          evidence_refs: [String.t()],
          text: String.t()
        }

  def from_map(map) do
    %__MODULE__{
      block_id: Map.fetch!(map, "block_id"),
      key: Map.fetch!(map, "key"),
      subject: Map.get(map, "subject"),
      status: Map.fetch!(map, "status"),
      confidence: Map.get(map, "confidence"),
      evidence_refs: Map.get(map, "evidence_refs", []),
      text: Map.fetch!(map, "text")
    }
  end
end

defmodule RelayMark.Manifest.Comparison do
  @moduledoc "Structured research comparison projection."

  defstruct block_id: nil,
            title: nil,
            subjects: [],
            criteria: [],
            values: %{},
            preferred: nil,
            layout: nil,
            evidence_refs: [],
            summary: nil

  @type t :: %__MODULE__{
          block_id: String.t(),
          title: String.t() | nil,
          subjects: [String.t()],
          criteria: [String.t()],
          values: map(),
          preferred: String.t() | nil,
          layout: String.t(),
          evidence_refs: [String.t()],
          summary: String.t()
        }

  def from_map(map) do
    %__MODULE__{
      block_id: Map.fetch!(map, "block_id"),
      title: Map.get(map, "title"),
      subjects: Map.get(map, "subjects", []),
      criteria: Map.get(map, "criteria", []),
      values: Map.get(map, "values", %{}),
      preferred: Map.get(map, "preferred"),
      layout: Map.fetch!(map, "layout"),
      evidence_refs: Map.get(map, "evidence_refs", []),
      summary: Map.fetch!(map, "summary")
    }
  end
end
