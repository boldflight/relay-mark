defmodule RelayMark.Schema do
  @moduledoc false

  @document_schema_path Path.expand(
                          "../../priv/relaymark/schemas/relaymark-document.schema.json",
                          __DIR__
                        )
  @diagnostic_schema_path Path.expand(
                            "../../priv/relaymark/schemas/relaymark-diagnostic.schema.json",
                            __DIR__
                          )

  @external_resource @document_schema_path
  @external_resource @diagnostic_schema_path

  @document_schema @document_schema_path
                   |> File.read!()
                   |> Jason.decode!()
                   |> JSV.build!(warnings: :silent)

  @diagnostic_schema @diagnostic_schema_path
                     |> File.read!()
                     |> Jason.decode!()
                     |> JSV.build!(warnings: :silent)

  @spec validate_document_schema(term()) :: :ok | {:error, JSV.ValidationError.t()}
  def validate_document_schema(document), do: validate(@document_schema, document)

  @spec validate_diagnostic_schema(term()) :: :ok | {:error, JSV.ValidationError.t()}
  def validate_diagnostic_schema(diagnostic), do: validate(@diagnostic_schema, diagnostic)

  @spec diagnostic(JSV.ValidationError.t()) :: RelayMark.Diagnostic.t()
  def diagnostic(%JSV.ValidationError{} = error) do
    normalized = JSV.normalize_error(error, keys: :strings, sort: :asc)
    units = error_units(normalized)

    unit =
      Enum.max_by(
        units,
        &instance_location_specificity/1,
        fn -> %{"instanceLocation" => "#"} end
      )

    options =
      [path: normalize_instance_location(unit["instanceLocation"])]
      |> maybe_put_meta(diagnostic_meta(units, unit))

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

  defp validate(schema, value) do
    case JSV.validate(value, schema, cast: false) do
      {:ok, _validated} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp error_units(value) when is_list(value), do: Enum.flat_map(value, &error_units/1)

  defp error_units(%{} = value) do
    current = if is_binary(value["instanceLocation"]), do: [value], else: []
    current ++ Enum.flat_map(Map.values(value), &error_units/1)
  end

  defp error_units(_value), do: []

  defp instance_location_specificity(unit) do
    location = unit["instanceLocation"]
    {length(String.split(location, "/", trim: true)), byte_size(location)}
  end

  defp normalize_instance_location("#"), do: ""
  defp normalize_instance_location("#" <> pointer), do: pointer
  defp normalize_instance_location(pointer), do: pointer

  defp diagnostic_meta(units, unit) do
    reasons =
      units
      |> Enum.flat_map(&Map.get(&1, "errors", []))
      |> Enum.map(&Map.get(&1, "kind"))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.join(",")

    %{}
    |> maybe_put_value("reason", reasons)
    |> maybe_put_value("schema_location", unit["schemaLocation"])
  end

  defp maybe_put_value(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put_value(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_meta(options, meta) when map_size(meta) == 0, do: options
  defp maybe_put_meta(options, meta), do: Keyword.put(options, :meta, meta)
end
