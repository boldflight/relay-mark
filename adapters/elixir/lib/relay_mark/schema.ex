defmodule RelayMark.Schema do
  @moduledoc false
  # The packaged RelayMark JSON Schemas, checked by the canonical engine.

  @schemas %{
    document:
      {"relaymark-document.schema.json", "relaymark.schema.invalid",
       "Document does not conform to the RelayMark document schema."},
    manifest:
      {"relaymark-manifest.schema.json", "relaymark.manifest.schema.invalid",
       "Manifest does not conform to the RelayMark manifest schema."},
    diagnostic:
      {"relaymark-diagnostic.schema.json", "relaymark.diagnostic.schema.invalid",
       "Diagnostic does not conform to the RelayMark diagnostic schema."},
    layer_composition:
      {"relaymark-layer-composition.schema.json", "relaymark.layer_composition.schema.invalid",
       "Layer composition does not conform to the RelayMark layer composition schema."}
  }

  def validate_document_schema(document), do: validate(document, :document)
  def validate_manifest_schema(manifest), do: validate(manifest, :manifest)
  def validate_diagnostic_schema(diagnostic), do: validate(diagnostic, :diagnostic)

  def validate_layer_composition_schema(composition),
    do: validate(composition, :layer_composition)

  @spec validate(term(), :document | :manifest | :diagnostic | :layer_composition) ::
          :ok | {:error, [RelayMark.Diagnostic.t()]}
  def validate(value, subject) do
    {schema, code, message} = Map.fetch!(@schemas, subject)

    case RelayMark.Engine.json("schema", value, %{"schema" => schema}) do
      {:ok, errors} -> result(errors, subject)
      {:error, _} -> {:error, [RelayMark.Diagnostic.error(code, message)]}
    end
  end

  @doc false
  # The engine's schema errors for `subject` as one diagnostic at the deepest
  # failing instance path.
  @spec result([map()], atom()) :: :ok | {:error, [RelayMark.Diagnostic.t()]}
  def result([], _subject), do: :ok

  def result(errors, subject) do
    {_schema, code, message} = Map.fetch!(@schemas, subject)

    path =
      errors
      |> Enum.map(&(&1["instance_path"] || ""))
      |> Enum.max_by(&{length(String.split(&1, "/", trim: true)), byte_size(&1)})

    {:error, [RelayMark.Diagnostic.error(code, message, path: path)]}
  end
end
