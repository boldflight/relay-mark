defmodule RelayMark.Scripture.Source do
  @moduledoc "Immutable source identity for a portable Scripture release."

  defstruct name: nil, uri: nil, digest: nil

  @type t :: %__MODULE__{name: String.t(), uri: String.t(), digest: String.t()}

  def from_map(map) do
    %__MODULE__{
      name: Map.fetch!(map, "name"),
      uri: Map.fetch!(map, "uri"),
      digest: Map.fetch!(map, "digest")
    }
  end
end

defmodule RelayMark.Scripture.License do
  @moduledoc "License and attribution identity for a portable Scripture release."

  defstruct id: nil, name: nil, url: nil

  @type t :: %__MODULE__{id: String.t(), name: String.t(), url: String.t()}

  def from_map(map) do
    %__MODULE__{
      id: Map.fetch!(map, "id"),
      name: Map.fetch!(map, "name"),
      url: Map.fetch!(map, "url")
    }
  end
end

defmodule RelayMark.Scripture.Provenance do
  @moduledoc "Content-addressed provenance for a portable Scripture release."

  defstruct coordinate_inventory_digest: nil,
            normalized_index_input_digest: nil,
            source_archive_digest: nil,
            authority: nil,
            imported_at: nil

  @type t :: %__MODULE__{
          coordinate_inventory_digest: String.t(),
          normalized_index_input_digest: String.t(),
          source_archive_digest: String.t() | nil,
          authority: String.t() | nil,
          imported_at: String.t() | nil
        }

  def from_map(map) do
    %__MODULE__{
      coordinate_inventory_digest: Map.fetch!(map, "coordinate_inventory_digest"),
      normalized_index_input_digest: Map.fetch!(map, "normalized_index_input_digest"),
      source_archive_digest: Map.get(map, "source_archive_digest"),
      authority: Map.get(map, "authority"),
      imported_at: Map.get(map, "imported_at")
    }
  end
end

defmodule RelayMark.Scripture.Release do
  @moduledoc "Typed relaymark.scripture_release resource properties."

  alias RelayMark.Scripture

  defstruct profile: "relaymark.scripture_release",
            translation_id: nil,
            edition_id: nil,
            corpus_release_id: nil,
            versification_id: nil,
            source: nil,
            license: nil,
            attribution: nil,
            provenance: nil

  @type t :: %__MODULE__{
          profile: String.t(),
          translation_id: String.t(),
          edition_id: String.t(),
          corpus_release_id: String.t(),
          versification_id: String.t(),
          source: Scripture.Source.t(),
          license: Scripture.License.t(),
          attribution: String.t(),
          provenance: Scripture.Provenance.t()
        }

  def from_map(map) do
    %__MODULE__{
      profile: Map.fetch!(map, "profile"),
      translation_id: Map.fetch!(map, "translation_id"),
      edition_id: Map.fetch!(map, "edition_id"),
      corpus_release_id: Map.fetch!(map, "corpus_release_id"),
      versification_id: Map.fetch!(map, "versification_id"),
      source: map |> Map.fetch!("source") |> Scripture.Source.from_map(),
      license: map |> Map.fetch!("license") |> Scripture.License.from_map(),
      attribution: Map.fetch!(map, "attribution"),
      provenance: map |> Map.fetch!("provenance") |> Scripture.Provenance.from_map()
    }
  end
end

defmodule RelayMark.Scripture.Coordinate do
  @moduledoc "Lossless chapter-or-section Scripture coordinate."

  defstruct kind: nil,
            book_id: nil,
            chapter: nil,
            section_id: nil,
            verse_label: nil

  @type t :: %__MODULE__{
          kind: :chapter | :section,
          book_id: String.t(),
          chapter: pos_integer() | nil,
          section_id: String.t() | nil,
          verse_label: String.t()
        }

  def from_map(%{
        "coordinate_kind" => "chapter",
        "book_id" => book_id,
        "chapter" => chapter,
        "verse_label" => verse_label
      }) do
    %__MODULE__{
      kind: :chapter,
      book_id: book_id,
      chapter: chapter,
      verse_label: verse_label
    }
  end

  def from_map(%{
        "coordinate_kind" => "section",
        "book_id" => book_id,
        "section_id" => section_id,
        "verse_label" => verse_label
      }) do
    %__MODULE__{
      kind: :section,
      book_id: book_id,
      section_id: section_id,
      verse_label: verse_label
    }
  end
end

defmodule RelayMark.Scripture.Span do
  @moduledoc "Typed relaymark.scripture_span selector."

  alias RelayMark.Scripture

  defstruct profile: "relaymark.scripture_span",
            start: nil,
            end: nil,
            content_digest: nil,
            display_label: nil

  @type t :: %__MODULE__{
          profile: String.t(),
          start: Scripture.Coordinate.t(),
          end: Scripture.Coordinate.t(),
          content_digest: String.t(),
          display_label: String.t() | nil
        }

  def from_map(map) do
    %__MODULE__{
      profile: Map.fetch!(map, "profile"),
      start: map |> Map.fetch!("start") |> Scripture.Coordinate.from_map(),
      end: map |> Map.fetch!("end") |> Scripture.Coordinate.from_map(),
      content_digest: Map.fetch!(map, "content_digest"),
      display_label: Map.get(map, "display_label")
    }
  end
end

defmodule RelayMark.Scripture.Evidence do
  @moduledoc "Typed Scripture evidence projected from a manifest source."

  alias RelayMark.Scripture

  defstruct evidence_id: nil,
            source_id: nil,
            source_revision: nil,
            span: nil,
            release: nil,
            scope: nil,
            excerpt: nil

  @type t :: %__MODULE__{
          evidence_id: String.t(),
          source_id: String.t(),
          source_revision: String.t(),
          span: Scripture.Span.t(),
          release: Scripture.Release.t(),
          scope: String.t(),
          excerpt: String.t()
        }

  def from_manifest_source(%RelayMark.Manifest.Source{
        kind: "evidence_ref",
        source_type: "scripture",
        evidence_id: evidence_id,
        source_id: source_id,
        source_revision: source_revision,
        selector: selector,
        scripture_release: %Scripture.Release{} = release,
        scope: scope,
        excerpt: excerpt
      }) do
    {:ok,
     %__MODULE__{
       evidence_id: evidence_id,
       source_id: source_id,
       source_revision: source_revision,
       span: Scripture.Span.from_map(selector),
       release: release,
       scope: scope,
       excerpt: excerpt
     }}
  end

  def from_manifest_source(_source), do: :error
end
