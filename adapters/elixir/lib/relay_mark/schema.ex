defmodule RelayMark.SchemaCompiler do
  @moduledoc false

  defmacro function_from_relative_file(function_name, relative_path) do
    path = Path.expand(relative_path, Path.dirname(__CALLER__.file))
    schema = path |> File.read!() |> prepare_schema()

    quote do
      Exonerate.function_from_string(
        :def,
        unquote(function_name),
        unquote(schema),
        draft: "2020-12"
      )
    end
  end

  # Exonerate 1.2 treats any map entry named "id" as a legacy schema id,
  # including a definition stored at `$defs.id`. Rename that local definition
  # and its internal references in memory; this does not alter the canonical
  # schema or the validation contract.
  defp prepare_schema(schema_json) do
    schema = Jason.decode!(schema_json)

    case schema do
      %{"$defs" => %{"id" => identifier} = definitions} ->
        schema
        |> Map.put("$defs", definitions |> Map.delete("id") |> Map.put("identifier", identifier))
        |> rewrite_identifier_refs()
        |> Jason.encode!()

      _other ->
        schema_json
    end
  end

  defp rewrite_identifier_refs(%{} = value) do
    Map.new(value, fn
      {"$ref", "#/$defs/id"} -> {"$ref", "#/$defs/identifier"}
      {key, child} -> {key, rewrite_identifier_refs(child)}
    end)
  end

  defp rewrite_identifier_refs(value) when is_list(value),
    do: Enum.map(value, &rewrite_identifier_refs/1)

  defp rewrite_identifier_refs(value), do: value
end

defmodule RelayMark.Schema do
  @moduledoc false

  @document_schema_path Path.expand(
                          "../../../../spec/relaymark/schemas/relaymark-document.schema.json",
                          __DIR__
                        )
  @diagnostic_schema_path Path.expand(
                            "../../../../spec/relaymark/schemas/relaymark-diagnostic.schema.json",
                            __DIR__
                          )

  @external_resource @document_schema_path
  @external_resource @diagnostic_schema_path

  require Exonerate
  require RelayMark.SchemaCompiler

  RelayMark.SchemaCompiler.function_from_relative_file(
    :validate_document_schema,
    "../../../../spec/relaymark/schemas/relaymark-document.schema.json"
  )

  RelayMark.SchemaCompiler.function_from_relative_file(
    :validate_diagnostic_schema,
    "../../../../spec/relaymark/schemas/relaymark-diagnostic.schema.json"
  )

  @spec diagnostic(keyword()) :: RelayMark.Diagnostic.t()
  def diagnostic(error) when is_list(error) do
    meta =
      error
      |> Keyword.take([:absolute_keyword_location, :reason, :required, :expected])
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

    options =
      [path: Keyword.get(error, :instance_location)]
      |> maybe_put_meta(meta)

    RelayMark.Diagnostic.error(
      "relaymark.schema.invalid",
      "Document does not conform to the RelayMark document schema.",
      options
    )
  end

  def diagnostic(_error) do
    RelayMark.Diagnostic.error(
      "relaymark.schema.invalid",
      "Document does not conform to the RelayMark document schema."
    )
  end

  defp maybe_put_meta(options, meta) when map_size(meta) == 0, do: options
  defp maybe_put_meta(options, meta), do: Keyword.put(options, :meta, meta)
end
