defmodule RelayMark do
  @moduledoc """
  Elixir adapter for RelayMark AST and manifest JSON.

  This package intentionally models the portable RelayMark contract. Relay app
  persistence, authorization, and action execution belong in client projects.
  """

  alias RelayMark.{
    AgentAnswer,
    Document,
    Manifest,
    ManifestProjection,
    Schema,
    SemanticValidator,
    ValidationError
  }

  @doc "Imports CommonMark/directives or the exact relaymark-ast source declaration."
  def parse_document(source, options \\ []), do: RelayMark.DocumentSource.parse(source, options)

  @doc "Converts finite historical AST input once; callers retain originals and the identity mapping."
  def import_document(document, options \\ []),
    do: RelayMark.DocumentImport.import(document, options)

  @doc "Imports finite historical XML once and records exact identity attribute changes for the existing CRDT owner."
  def import_document_snapshot(snapshot, options \\ []),
    do: RelayMark.DocumentXML.import_snapshot(snapshot, options)

  @doc "Imports finite historical source using the same grammar and identity migration. Originals remain caller-owned evidence."
  def import_source(source, options \\ []),
    do: RelayMark.DocumentSource.import_source(source, options)

  @doc "Writes exact source interchange, retaining identities and authored metadata."
  def serialize_document(document), do: RelayMark.DocumentSource.serialize(document)
  @doc "Projects readable Markdown; this projection is never a second writable body."
  def project_document_markdown(document), do: RelayMark.DocumentSource.project_markdown(document)

  @doc "Renders authored semantics; host hydration and authorization remain outside."
  def render_document(document), do: RelayMark.DocumentRenderer.render(document)

  @doc "Parses the bounded authored source of an canonical EntityRef atom."
  @spec parse_entity_reference_source(binary()) :: {:ok, map()} | :error
  def parse_entity_reference_source(source),
    do: RelayMark.EntityReference.parse_source(source)

  @spec decode_layer_composition(binary()) :: {:ok, RelayMark.Composition.t()} | {:error, term()}
  def decode_layer_composition(json) when is_binary(json) do
    with {:ok, map} <- RelayMark.JSON.decode(json) do
      {:ok, RelayMark.Composition.from_map(map)}
    end
  end

  @spec validate_layer_composition(term()) :: :ok | {:error, [RelayMark.Diagnostic.t()]}
  def validate_layer_composition(composition) do
    case Schema.validate_layer_composition_schema(composition) do
      :ok -> :ok
      {:error, error} -> {:error, [Schema.diagnostic(error)]}
    end
  end

  @spec decode_document(binary()) :: {:ok, Document.t()} | {:error, term()}
  def decode_document(json) when is_binary(json) do
    with {:ok, map} <- RelayMark.JSON.decode(json) do
      {:ok, Document.from_map(map)}
    end
  end

  @spec decode_manifest(binary()) :: {:ok, Manifest.t()} | {:error, term()}
  def decode_manifest(json) when is_binary(json) do
    with {:ok, map} <- RelayMark.JSON.decode(json) do
      {:ok, Manifest.from_map(map)}
    end
  end

  @doc """
  Validates a canonical, JSON-keyed RelayMark document map.

  Structural validation is compiled from the canonical JSON Schema 2020-12
  document schema. Semantic validation applies the same directive, evidence,
  lifecycle, comparison, and identity rules as the reference runtime.
  """
  @spec validate_document(map(), map()) :: :ok | {:error, [RelayMark.Diagnostic.t()]}
  def validate_document(document, validation_context \\ %{}) do
    case Schema.validate_document_schema(document) do
      :ok ->
        case SemanticValidator.validate(document, validation_context) do
          [] -> :ok
          diagnostics -> {:error, diagnostics}
        end

      {:error, error} ->
        {:error, [Schema.diagnostic(error)]}
    end
  end

  @doc """
  Validates a canonical, JSON-keyed RelayMark projection manifest map.

  Structural validation is compiled from the canonical JSON Schema 2020-12
  manifest and diagnostic schemas bundled in the package.
  """
  @spec validate_manifest(term()) :: :ok | {:error, [RelayMark.Diagnostic.t()]}
  def validate_manifest(manifest) do
    case Schema.validate_manifest_schema(manifest) do
      :ok -> :ok
      {:error, error} -> {:error, [Schema.diagnostic(error, :manifest)]}
    end
  end

  @doc """
  Projects a canonical RelayMark document map into its portable manifest.

  Hosts should use this function instead of maintaining a parallel manifest
  projector so newly added portable directives remain consistent everywhere.
  """
  @spec project_manifest(map(), [map()]) :: map()
  def project_manifest(document, diagnostics \\ []) do
    ManifestProjection.project(document, diagnostics)
  end

  @doc """
  Validates one exact transported Agent Answer document/manifest JSON pair.

  Success returns decoded value models plus SHA-256 digests of the exact input
  bytes. Any semantic or canonical projection mismatch is rejected.
  """
  @spec validate_transported_agent_answer_pair(binary(), binary(), map()) ::
          {:ok, AgentAnswer.validated_pair()} | {:error, [RelayMark.Diagnostic.t()]}
  def validate_transported_agent_answer_pair(
        document_json,
        manifest_json,
        validation_context \\ %{}
      ) do
    AgentAnswer.validate_transported_pair(document_json, manifest_json, validation_context)
  end

  @doc """
  Validates and returns a canonical RelayMark document, raising on failure.
  """
  @spec validate_document!(map(), map()) :: map()
  def validate_document!(document, validation_context \\ %{}) do
    case validate_document(document, validation_context) do
      :ok -> document
      {:error, diagnostics} -> raise ValidationError, diagnostics: diagnostics
    end
  end
end
