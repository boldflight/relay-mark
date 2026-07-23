defmodule RelayMark do
  @moduledoc """
  Elixir adapter for RelayMark AST and manifest JSON.

  This package intentionally models the portable RelayMark contract. Relay app
  persistence, authorization, and action execution belong in client projects.
  """

  alias RelayMark.{Document, Manifest, Schema, SemanticValidator, ValidationError}

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
  @spec validate_document(map()) :: :ok | {:error, [RelayMark.Diagnostic.t()]}
  def validate_document(document) do
    case Schema.validate_document_schema(document) do
      :ok ->
        case SemanticValidator.validate(document) do
          [] -> :ok
          diagnostics -> {:error, diagnostics}
        end

      {:error, error} ->
        {:error, [Schema.diagnostic(error)]}
    end
  end

  @doc """
  Validates and returns a canonical RelayMark document, raising on failure.
  """
  @spec validate_document!(map()) :: map()
  def validate_document!(document) do
    case validate_document(document) do
      :ok -> document
      {:error, diagnostics} -> raise ValidationError, diagnostics: diagnostics
    end
  end
end
