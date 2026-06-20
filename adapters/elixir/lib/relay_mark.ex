defmodule RelayMark do
  @moduledoc """
  Dependency-free Elixir adapter for RelayMark AST and manifest JSON.

  This package intentionally models the portable RelayMark contract. Relay app
  persistence, authorization, and action execution belong in client projects.
  """

  alias RelayMark.{Document, Manifest}

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
end
