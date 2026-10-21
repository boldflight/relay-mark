defmodule RelayMark do
  @moduledoc """
  Elixir adapter for RelayMark AST and manifest JSON.

  Every conversion and validation runs in the canonical RelayMark engine
  (`relaymark-core`, Rust) through one NIF, so the server produces what the
  web and native clients produce. This package keeps the Elixir value models.
  Relay app persistence, authorization, and action execution belong in client
  projects.
  """

  alias RelayMark.{AgentAnswer, Document, Engine, Manifest, Schema, ValidationError}

  @source_error "relaymark.source.invalid"

  @doc "Imports CommonMark/directives or the exact relaymark-ast source declaration."
  def parse_document(source, options \\ [])

  def parse_document(source, options) when is_binary(source) do
    namespace = Keyword.get(options, :namespace)

    if is_nil(namespace) or is_binary(namespace),
      do: source_result(Engine.source("parse", source, compact(%{"namespace" => namespace}))),
      else: source_error("import_namespace")
  end

  def parse_document(_, _), do: source_error("input")

  @doc "Normalize authored semantics while preserving all block/option IDs and envelope metadata."
  def normalize_document(document), do: RelayMark.DocumentXML.normalize_document(document)

  @doc "Converts finite historical AST input once; callers retain originals and the identity mapping."
  def import_document(document, options \\ []) do
    with {:ok, namespace} <- namespace(options, "relaymark.import.invalid") do
      Engine.json("import_document", document, %{"namespace" => namespace})
      |> keyed_error("relaymark.import.invalid")
      |> imported()
    end
  end

  @doc "Imports finite historical XML once and records exact identity attribute changes for the existing CRDT owner."
  def import_document_snapshot(snapshot, options \\ []),
    do: RelayMark.DocumentXML.import_snapshot(snapshot, options)

  @doc "Imports finite historical source using the same grammar and identity migration. Originals remain caller-owned evidence."
  def import_source(source, options \\ [])

  def import_source(source, options) when is_binary(source) do
    case Keyword.get(options, :namespace) do
      namespace when is_binary(namespace) and namespace != "" ->
        source_result(Engine.source("import_source", source, %{"namespace" => namespace}))
        |> imported()

      _ ->
        source_error("import_namespace")
    end
  end

  def import_source(_, _), do: source_error("import_namespace")

  @doc "Writes exact source interchange, retaining identities and authored metadata."
  def serialize_document(document), do: source_result(Engine.text("serialize", document))

  @doc "Projects readable Markdown; this projection is never a second writable body."
  def project_document_markdown(document), do: source_result(Engine.text("markdown", document))

  @doc "Derives readable Markdown and safe static HTML through one strict preparation."
  def project_document(document) do
    case source_result(Engine.json("project", document)) do
      {:ok, %{"body" => body, "body_html" => html}} -> {:ok, %{body: body, body_html: html}}
      error -> error
    end
  end

  @doc "Renders authored semantics; host hydration and authorization remain outside."
  def render_document(document),
    do: Engine.text("html", document) |> keyed_error("relaymark.document_xml.invalid")

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
  def validate_layer_composition(composition),
    do: Schema.validate(composition, :layer_composition)

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
  Validates a canonical, JSON-keyed RelayMark document map: the RelayMark
  document JSON Schema, then the directive, evidence, lifecycle, comparison
  and identity rules of the reference runtime.
  """
  @spec validate_document(map(), map()) :: :ok | {:error, [RelayMark.Diagnostic.t()]}
  def validate_document(document, validation_context \\ %{}) do
    # One call: a large paper crosses the NIF boundary as JSON once.
    case Engine.json("validate_document", document, %{"context" => validation_context}) do
      {:ok, %{"schema" => [_ | _] = errors}} ->
        Schema.result(errors, :document)

      {:ok, %{"diagnostics" => []}} ->
        :ok

      {:ok, %{"diagnostics" => diagnostics}} ->
        {:error, diagnostics}

      {:error, reason} ->
        {:error, [RelayMark.Diagnostic.error("relaymark.schema.invalid", reason)]}
    end
  end

  @doc "Validates a canonical, JSON-keyed RelayMark projection manifest map against its JSON Schema."
  @spec validate_manifest(term()) :: :ok | {:error, [RelayMark.Diagnostic.t()]}
  def validate_manifest(manifest), do: Schema.validate(manifest, :manifest)

  @doc """
  Projects a canonical RelayMark document map into its portable manifest.

  Hosts should use this function instead of maintaining a parallel manifest
  projector so newly added portable directives remain consistent everywhere.
  """
  @spec project_manifest(map(), [map()]) :: map()
  def project_manifest(document, diagnostics \\ []) do
    {:ok, manifest} = Engine.json("manifest", document, %{"diagnostics" => diagnostics})
    manifest
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

  @doc "Finite saved publication conversion; optional source must be the same immutable released body."
  def import_form_publication(publication, options \\ []) do
    code = "relaymark.form_publication_import.invalid"

    with {:ok, namespace} <- namespace(options, code) do
      options = compact(%{"namespace" => namespace, "source" => Keyword.get(options, :source)})

      case Engine.json("form_publication", publication, options) |> keyed_error(code) do
        {:ok, result} ->
          {:ok,
           %{
             document: result["document"],
             identity_mapping: result["identity_mapping"],
             normalizations: result["normalizations"]
           }}

        error ->
          error
      end
    end
  end

  defp namespace(options, code) do
    case Keyword.get(options, :namespace) do
      namespace when is_binary(namespace) and namespace != "" -> {:ok, namespace}
      _ -> {:error, [%{"level" => "error", "code" => code, "reason" => "import_namespace"}]}
    end
  end

  defp imported({:ok, result}),
    do: {:ok, %{document: result["document"], identity_mapping: result["identity_mapping"]}}

  defp imported(error), do: error

  defp compact(map), do: map |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new()

  defp source_result({:ok, _} = ok), do: ok
  defp source_result({:error, reason}), do: source_error(reason)

  defp source_error(reason),
    do: {:error, [%{level: "critical", code: @source_error, reason: reason}]}

  @doc false
  def keyed_error({:ok, _} = ok, _code), do: ok

  def keyed_error({:error, reason}, code),
    do: {:error, [%{"level" => "error", "code" => code, "reason" => reason}]}
end
