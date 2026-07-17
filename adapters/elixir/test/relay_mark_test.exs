defmodule RelayMarkTest do
  use ExUnit.Case, async: true

  test "decodes an inline entity reference with an id as inline content" do
    json =
      ~S({"type":"relaymark.document","version":1,"blocks":[{"id":"b1","type":"paragraph","content":[{"type":"relay.entity_ref","id":"product-1","label":"Mac mini"}]}]})

    assert {:ok, document} = RelayMark.decode_document(json)
    assert [%RelayMark.Block{content: [%RelayMark.Inline{} = reference]}] = document.blocks
    assert reference.type == "relay.entity_ref"
    assert reference.id == "product-1"
    assert reference.label == "Mac mini"
  end

  test "decodes RelayMark document fixture" do
    assert {:ok, document} =
             "../../../spec/relaymark/examples/mentor-meeting.ast.json"
             |> fixture()
             |> RelayMark.decode_document()

    assert document.type == "relaymark.document"
    assert document.version == 1
    assert document.frontmatter["title"] == "Marcus interview prep"
    assert length(document.blocks) == 5

    source_bundle = Enum.at(document.blocks, 2)
    assert source_bundle.id == "src-1"
    assert source_bundle.type == "relay.source_bundle"
    assert source_bundle.props["scope"] == "private"
    assert hd(source_bundle.content).type == "relay.transcript_segment"

    action = Enum.at(document.blocks, 4)
    assert action.type == "relay.action_row"
    assert action.props["action"] == "relay.task.create"
    assert action.evidence_refs == ["src-1"]
    assert RelayMark.Block.plain_text(action) == "Send interview prep resources before Thursday."
  end

  test "decodes RelayMark manifest fixture" do
    assert {:ok, manifest} =
             "../../../spec/relaymark/examples/mentor-meeting.manifest.json"
             |> fixture()
             |> RelayMark.decode_manifest()

    assert manifest.type == "relaymark.manifest"
    assert [action] = manifest.actions
    assert action.block_id == "b5"
    assert action.action == "relay.task.create"
    assert action.args["title"] == "Send interview prep resources before Thursday."
    assert Enum.map(manifest.sources, & &1.kind) == ["source_bundle", "transcript_range"]
    assert manifest.diagnostics == []
  end

  test "decodes product research document fixture with inline product refs and source blocks" do
    assert {:ok, document} =
             "../../../spec/relaymark/examples/product-research.ast.json"
             |> fixture()
             |> RelayMark.decode_document()

    assert length(document.blocks) == 9

    intro = Enum.at(document.blocks, 1)
    assert %RelayMark.Inline{} = product_ref = Enum.at(intro.content, 1)
    assert product_ref.type == "relay.product_ref"
    assert product_ref.id == "product-mac-mini-m4-pro"

    source_bundle = Enum.at(document.blocks, 2)
    assert Enum.map(source_bundle.content, & &1.type) == ["relay.url_ref", "relay.url_ref"]

    comparison = Enum.at(document.blocks, 4)
    assert comparison.type == "relay.comparison"
    assert comparison.evidence_refs == ["src-apple", "src-mbench"]

    assert RelayMark.Block.plain_text(comparison) ==
             "Mac mini with M4 Pro is the lower-cost fit; Mac Studio with M4 Max leads on memory bandwidth and the imported CPU score."
  end

  test "decodes product research manifest projections" do
    assert {:ok, manifest} =
             "../../../spec/relaymark/examples/product-research.manifest.json"
             |> fixture()
             |> RelayMark.decode_manifest()

    assert Enum.map(manifest.actions, & &1.review) == ["accepted", "rejected"]

    assert Enum.map(manifest.references, & &1.type) == [
             "relay.product_ref",
             "relay.product_ref",
             "relay.entity_ref",
             "relay.product_ref",
             "relay.product_ref"
           ]

    assert Enum.map(manifest.claims, & &1.status) == ["disputed", "disputed"]
    assert [comparison] = manifest.comparisons
    assert comparison.layout == "table"
    assert comparison.preferred == "entity:product-mac-mini-m4-pro"
    assert comparison.values["price_usd"]["entity:product-mac-mini-m4-pro"] == 1399
  end

  defp fixture(relative_path) do
    __DIR__
    |> Path.join(relative_path)
    |> Path.expand()
    |> File.read!()
  end
end
