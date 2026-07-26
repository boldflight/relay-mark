defmodule RelayMark do
  @moduledoc """
  Elixir adapter for RelayMark AST and manifest JSON.

  This package intentionally models the portable RelayMark contract. Relay app
  persistence, authorization, and action execution belong in client projects.
  """

  alias RelayMark.{AgentAnswer, Document, Manifest, Schema, SemanticValidator, ValidationError}

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
