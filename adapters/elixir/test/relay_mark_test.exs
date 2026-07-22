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
    assert source_bundle.id == "b3"
    assert source_bundle.props["id"] == "src-1"
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
    assert action.block_id == "b6"
    assert is_nil(action.proposal_id)
    assert is_nil(action.proposal_record_id)
    assert is_nil(action.proposal_revision)
    assert action.action == "relay.task.create"
    assert action.args["title"] == "Send interview prep resources before Thursday."
    assert Enum.map(manifest.sources, & &1.kind) == ["source_bundle", "transcript_range"]
    assert manifest.diagnostics == []
  end

  test "decodes stable evidence and lifecycle-aware action proposals" do
    assert {:ok, document} =
             "../../../spec/relaymark/examples/agent-paper-review.ast.json"
             |> fixture()
             |> RelayMark.decode_document()

    source_bundle = Enum.at(document.blocks, 2)
    assert source_bundle.id == "b3"
    assert source_bundle.props["id"] == "source-review-1"
    assert source_bundle.props["revision"] == 2

    assert Enum.map(source_bundle.content, & &1.type) == [
             "relay.evidence_ref",
             "relay.evidence_ref",
             "relay.evidence_ref"
           ]

    transcript_evidence = hd(source_bundle.content)
    assert transcript_evidence.id == "b4"
    assert transcript_evidence.props["id"] == "70000000-0000-4000-8000-000000000001"
    assert transcript_evidence.props["source_type"] == "transcript"

    assert {:ok, manifest} =
             "../../../spec/relaymark/examples/agent-paper-review.manifest.json"
             |> fixture()
             |> RelayMark.decode_manifest()

    assert Enum.map(manifest.actions, & &1.proposal_id) == [
             "practice-task",
             "coaching-touchpoint",
             "interview-journey",
             "practice-resource",
             "practice-follow-up"
           ]

    assert Enum.map(manifest.actions, & &1.proposal_record_id) == [
             "10000000-0000-4000-8000-000000000001",
             "10000000-0000-4000-8000-000000000002",
             "10000000-0000-4000-8000-000000000003",
             "10000000-0000-4000-8000-000000000004",
             "10000000-0000-4000-8000-000000000005"
           ]

    assert Enum.map(manifest.actions, & &1.proposal_revision) == [1, 2, 1, 1, 1]

    assert Enum.map(manifest.actions, & &1.review) == [
             "ready",
             "accepted",
             "rejected",
             "undone",
             "ready"
           ]

    assert Enum.at(manifest.actions, 1).execution_id ==
             "30000000-0000-4000-8000-000000000002"

    assert Enum.at(manifest.actions, 3).decision_id ==
             "20000000-0000-4000-8000-000000000004"

    assert Enum.at(manifest.actions, 3).undo_id ==
             "40000000-0000-4000-8000-000000000004"

    assert hd(manifest.actions).args["name"] == "Practice interview answers twice"
    assert hd(manifest.actions).args["title"] == "Create Jordan's edited practice task."
    assert List.last(manifest.actions).action == "follow_up_create"

    assert Enum.map(manifest.sources, & &1.kind) == [
             "source_bundle",
             "evidence_ref",
             "evidence_ref",
             "evidence_ref"
           ]

    transcript_source = Enum.at(manifest.sources, 1)
    assert transcript_source.block_id == "b4"
    assert transcript_source.evidence_id == "70000000-0000-4000-8000-000000000001"
    assert transcript_source.source_revision == "1"
    assert transcript_source.selector["start_ms"] == 724_000
    assert transcript_source.excerpt == "I will practice twice before Thursday."
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
