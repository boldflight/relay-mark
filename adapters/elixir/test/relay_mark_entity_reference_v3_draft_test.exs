defmodule RelayMarkEntityReferenceV3DraftTest do
  use ExUnit.Case, async: true

  alias RelayMark.Schema

  @fixture Path.expand(
             "../../../spec/relaymark/collaboration/fixtures/entity-reference-v3-draft.json",
             __DIR__
           )

  test "packaged contract accepts authored EntityRef identity from real TipTap/Yjs" do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    ast = fixture["expected_ast"]
    reference = Enum.at(ast["blocks"], 1)

    assert :ok = Schema.validate_document_schema(ast)
    assert :ok = RelayMark.validate_document(ast)
    assert reference["id"] == "b00000000000040008000000000000062"
    assert reference["type"] == "relay.entity_reference"

    assert reference["props"]["id"] ==
             "entity:#{fixture["normalized"] |> get_in(["content", Access.at(1), "attrs", "entityId"])}"

    assert reference["props"]["projection"] == "card"
    assert reference["props"]["source"] == fixture["authored_source"]
    assert reference["content"] == []
    assert {:ok, parsed} = RelayMark.parse_v3_entity_reference_source(fixture["authored_source"])

    assert Map.take(parsed, ["id", "entityId", "label", "projection", "source"]) == %{
             "id" => reference["props"]["id"],
             "entityId" =>
               get_in(fixture, ["normalized", "content", Access.at(1), "attrs", "entityId"]),
             "label" => reference["props"]["label"],
             "projection" => reference["props"]["projection"],
             "source" => fixture["authored_source"]
           }

    stale = put_in(ast, ["blocks", Access.at(1), "props", "label"], "Hydrated label")
    assert {:error, diagnostics} = RelayMark.validate_document(stale)
    assert Enum.map(diagnostics, & &1["code"]) == ["relaymark.entity_reference.source"]
  end

  test "bounded parser rejects invalid projection, identity, duplicate attrs and rich body" do
    source = @fixture |> File.read!() |> Jason.decode!() |> Map.fetch!("authored_source")

    for changed <- [
          String.replace(source, ~s(projection: "card"), ~s(projection: "inline")),
          String.replace(source, "entity:9f815b37", "entity:Other"),
          String.replace(
            source,
            ~s(label: "Ada Lovelace"),
            ~s(label: "Ada Lovelace", label: "Other")
          ),
          String.replace(source, "Authored fallback", "[[Task: hidden]]")
        ] do
      assert :error = RelayMark.parse_v3_entity_reference_source(changed)
    end
  end

  test "bounded parser preserves multiline authored defaults" do
    entity_id = "9f815b37-67b3-4101-868c-5335351feb6a"
    source = "@EntityRef(\r\n  id: \"entity:#{entity_id}\"\r\n) {\r\n  Fallback\r\n}"
    assert {:ok, parsed} = RelayMark.parse_v3_entity_reference_source(source)
    assert parsed["entityId"] == entity_id
    assert parsed["label"] == "Fallback"
    assert parsed["projection"] == "link"
    assert parsed["source"] == source
  end
end
