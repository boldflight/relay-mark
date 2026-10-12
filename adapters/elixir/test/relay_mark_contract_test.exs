defmodule RelayMark.ContractTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../../spec/relaymark", __DIR__)

  test "canonical descriptor shares one compatibility number and rejects old AST counter" do
    inputs = %{
      "editor_schema" => File.read!(Path.join(@root, "editor-schema.json")) |> Jason.decode!(),
      "xml_attribute_encoding" =>
        File.read!(Path.join(@root, "xml-attribute-encoding.json")) |> Jason.decode!()
    }

    schema_hash = :crypto.hash(:sha256, canonical_json(inputs)) |> Base.encode16(case: :lower)

    assert RelayMark.Contract.descriptor() == %{
             "contract_version" => 1,
             "schema" => "relaymark-prosemirror",
             "source_contract" => "relaymark_ast",
             "schema_hash" => schema_hash
           }

    ast = %{"type" => "relaymark.document", "blocks" => []}
    assert :ok = RelayMark.validate_document(ast)
    assert {:error, _} = RelayMark.validate_document(Map.put(ast, "version", 1))
  end

  defp canonical_json(value) when is_map(value) do
    fields =
      value
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, item} ->
        [Jason.encode!(key), ":", canonical_json(item)]
      end)

    ["{", Enum.intersperse(fields, ","), "}"]
  end

  defp canonical_json(value) when is_list(value),
    do: ["[", Enum.intersperse(Enum.map(value, &canonical_json/1), ","), "]"]

  defp canonical_json(value), do: Jason.encode!(value)
end
