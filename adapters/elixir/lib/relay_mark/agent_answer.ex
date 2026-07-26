defmodule RelayMark.AgentAnswer do
  @moduledoc """
  Portable validation for one transported Agent Answer document and manifest.

  The returned digests bind the exact accepted UTF-8 JSON bytes. They are host
  envelope metadata and are never inserted into the RelayMark document.
  """

  alias RelayMark.{Diagnostic, Document, JSON, Manifest, ManifestProjection}

  @profile "relaymark.agent_answer.v1"

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
    with {:ok, document} <- decode_json(document_json, "document"),
         {:ok, manifest} <- decode_json(manifest_json, "manifest") do
      diagnostics =
        if get_in(document, ["frontmatter", "profile"]) == @profile do
          case RelayMark.validate_document(document, validation_context) do
            :ok -> []
            {:error, diagnostics} -> diagnostics
          end
        else
          [
            Diagnostic.error(
              "relaymark.agent_answer.profile",
              "Transported Agent Answer document must declare frontmatter.profile relaymark.agent_answer.v1."
            )
          ]
        end

      diagnostics =
        if diagnostics == [] and ManifestProjection.project(document, []) != manifest do
          [
            Diagnostic.error(
              "relaymark.agent_answer.manifest_mismatch",
              "Transported relaymark.agent_answer.v1 manifest must exactly match the canonical projection of its document."
            )
          ]
        else
          diagnostics
        end

      if diagnostics == [] do
        {:ok,
         %{
           document: Document.from_map(document),
           manifest: Manifest.from_map(manifest),
           document_digest: digest(document_json),
           manifest_digest: digest(manifest_json)
         }}
      else
        {:error, diagnostics}
      end
    end
  end

  defp decode_json(json, label) do
    case JSON.decode(json) do
      {:ok, value} when is_map(value) ->
        {:ok, value}

      _error ->
        {:error,
         [
           Diagnostic.error(
             "relaymark.transport.#{label}_json",
             "Transported RelayMark #{label} must be valid UTF-8 JSON."
           )
         ]}
    end
  end

  defp digest(bytes) do
    "sha256:" <> (:crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower))
  end
end
