defmodule RelayMark.AgentAnswer do
  @moduledoc """
  Portable validation for one transported Agent Answer document and manifest.

  The returned digests bind the exact accepted UTF-8 JSON bytes. They are host
  envelope metadata and are never inserted into the RelayMark document.
  """

  alias RelayMark.{Diagnostic, Document, Manifest}

  @type validated_pair :: %{
          document: Document.t(),
          manifest: Manifest.t(),
          document_digest: String.t(),
          manifest_digest: String.t()
        }

  @spec validate_transported_pair(binary(), binary(), map()) ::
          {:ok, validated_pair()} | {:error, [Diagnostic.t()]}
  def validate_transported_pair(document_json, manifest_json, validation_context \\ %{})
      when is_binary(document_json) and is_binary(manifest_json) and
             is_map(validation_context) do
    with :ok <- json_object(document_json, "document"),
         :ok <- json_object(manifest_json, "manifest") do
      options = %{"manifest" => manifest_json, "context" => validation_context}

      case RelayMark.Engine.call("transported_pair", document_json, options) do
        {:ok, output} ->
          case Jason.decode!(output) do
            %{"diagnostics" => [], "document" => document, "manifest" => manifest} = result ->
              {:ok,
               %{
                 document: Document.from_map(document),
                 manifest: Manifest.from_map(manifest),
                 document_digest: result["document_digest"],
                 manifest_digest: result["manifest_digest"]
               }}

            %{"diagnostics" => diagnostics} ->
              {:error, diagnostics}
          end

        {:error, _} ->
          {:error, [json_error("document")]}
      end
    end
  end

  defp json_object(json, label) do
    case RelayMark.JSON.decode(json) do
      {:ok, value} when is_map(value) -> :ok
      _ -> {:error, [json_error(label)]}
    end
  end

  defp json_error(label),
    do:
      Diagnostic.error(
        "relaymark.transport.#{label}_json",
        "Transported RelayMark #{label} must be valid UTF-8 JSON."
      )
end
