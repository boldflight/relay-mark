defmodule RelayMarkPaperControlsDraftTest do
  use ExUnit.Case, async: true

  alias RelayMark.PaperControl
  alias RelayMark.Schema

  @fixture Path.expand(
             "../../../spec/relaymark/collaboration/fixtures/paper-controls-v3-draft.json",
             __DIR__
           )

  test "packaged contract accepts the real TipTap/Yjs control fixture" do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    ast = fixture["expected_ast"]

    assert :ok = Schema.validate_document_schema(ast)
    assert :ok = RelayMark.validate_document(ast)

    assert Enum.map(ast["blocks"], & &1["type"]) == [
             "paragraph",
             "relay.paper_control",
             "relay.paper_control",
             "relay.paper_control",
             "relay.paper_control",
             "relay.paper_control",
             "paragraph"
           ]

    for block <- Enum.filter(ast["blocks"], &(&1["type"] == "relay.paper_control")) do
      props = block["props"]
      assert block["content"] == []
      assert {:ok, props["source"]} == PaperControl.canonical_source(Map.delete(props, "source"))
      assert PaperControl.valid_block?(block)
    end
  end

  test "source drift and host state are rejected" do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    ast = fixture["expected_ast"]
    drift = put_in(ast, ["blocks", Access.at(2), "props", "target"], "other")
    assert {:error, diagnostics} = RelayMark.validate_document(drift)
    assert "relaymark.paper_control.source" in Enum.map(diagnostics, & &1["code"])

    hydrated = put_in(ast, ["blocks", Access.at(2), "props", "authorized"], true)
    assert {:error, diagnostics} = RelayMark.validate_document(hydrated)
    assert "relaymark.paper_control.source" in Enum.map(diagnostics, & &1["code"])
  end
end
