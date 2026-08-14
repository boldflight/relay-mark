defmodule RelayMarkTest do
  use ExUnit.Case, async: true

  test "decodes and projects the portable Person Paper composition contract" do
    ast = fixture("../../../spec/relaymark/examples/person-paper.ast.json")
    manifest_json = fixture("../../../spec/relaymark/examples/person-paper.manifest.json")

    assert {:ok, document} = RelayMark.decode_document(ast)
    assert Enum.map(document.blocks, & &1.type) == [
             "heading",
             "relay.property_sheet",
             "paragraph",
             "relay.data_view",
             "relay.data_view"
           ]

    assert {:ok, manifest} = RelayMark.decode_manifest(manifest_json)
    assert [sheet] = manifest.property_sheets
    assert sheet.binding == "paper.person.properties"
    assert sheet.fields == ["full_name", "emails", "phones", "company"]
    assert Enum.map(manifest.data_views, & &1.source) == [
             "paper.related_commitments",
             "paper.journey_summary"
           ]

    assert ast |> Jason.decode!() |> RelayMark.ManifestProjection.project() ==
             Jason.decode!(manifest_json)
  end

  test "decodes and validates portable semantic layer contribution metadata" do
    json = fixture("../../../spec/relaymark/examples/layered-meeting.composition.json")
    map = Jason.decode!(json)

    assert :ok = RelayMark.validate_layer_composition(map)
    assert {:ok, composition} = RelayMark.decode_layer_composition(json)
    assert Enum.map(composition.layers, & &1.role) == ["authored", "generated", "source", "discussion"]
    generated = Enum.at(composition.layers, 1)
    assert Enum.at(generated.items, 0).placement.anchor.block_id == "meeting_heading"
    assert Enum.at(generated.items, 1).placement.anchor_state == "stale"
    assert Enum.at(generated.items, 1).placement.fallback == "append_to_layer"
    discussion = Enum.at(composition.layers, 3)
    assert hd(discussion.items).placement.anchor_state == "undisclosed"
    assert is_nil(hd(discussion.items).placement.anchor)
  end

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

  test "validates RelayMark manifest structure through the package API" do
    manifest =
      "../../../spec/relaymark/examples/mentor-meeting.manifest.json"
      |> fixture()
      |> Jason.decode!()

    assert :ok = RelayMark.validate_manifest(manifest)

    invalid_manifest = put_in(manifest, ["actions", Access.at(0), "review"], "published")

    assert {:error, [diagnostic]} = RelayMark.validate_manifest(invalid_manifest)
    assert diagnostic["code"] == "relaymark.manifest.schema.invalid"
    assert diagnostic["level"] == "error"
    assert diagnostic["path"] == "/actions/0/review"
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

  test "decodes the canonical answered Scripture Ask paper and its evidence projection" do
    assert {:ok, document} =
             "../../../spec/relaymark/examples/scripture-ask-answered.ast.json"
             |> fixture()
             |> RelayMark.decode_document()

    assert %{
             "profile" => "relaymark.agent_answer.v1",
             "outcome" => "answered",
             "question" => "What does Acts 18:2-3 say about Aquila and Priscilla?",
             "question_id" =>
               "sha256:6640f17d592931bf54f6d3bdf1c1b5f1a7a302bcdc4b7a2e626fd9671b6a1da8"
           } = document.frontmatter

    assert [answer_heading, claim, evidence_heading, source_bundle] = document.blocks
    assert answer_heading.type == "heading"

    assert RelayMark.Block.plain_text(answer_heading) ==
             "What Acts says about Aquila and Priscilla"

    assert claim.type == "relay.claim"
    assert claim.props["key"] == "scripture.ask.aquila-priscilla.acts-18-2-3"
    assert claim.props["status"] == "supported"
    assert claim.evidence_refs == ["urn:relay:scripture:evidence:acts-18-2-3"]

    assert RelayMark.Block.plain_text(claim) ==
             "Acts 18:2-3 identifies Aquila as a Jewish man from Pontus, names Priscilla as his wife, and says their occupation was tentmaking."

    assert RelayMark.Block.plain_text(evidence_heading) == "Evidence"
    assert [evidence_block] = source_bundle.content
    assert evidence_block.type == "relay.evidence_ref"
    assert evidence_block.props["id"] == "urn:relay:scripture:evidence:acts-18-2-3"
    assert evidence_block.props["source"] == "askScriptureRelease1"

    assert [release_resource] = document.resources
    assert {:ok, release} = RelayMark.Resource.scripture_release(release_resource)
    assert release.corpus_release_id == "urn:relay:scripture:corpus:kjv:1769-fixture-1"

    assert {:ok, manifest} =
             "../../../spec/relaymark/examples/scripture-ask-answered.manifest.json"
             |> fixture()
             |> RelayMark.decode_manifest()

    assert [claim_projection] = manifest.claims
    assert claim_projection.block_id == "askClaim1"
    assert claim_projection.key == "scripture.ask.aquila-priscilla.acts-18-2-3"
    assert claim_projection.status == "supported"
    assert claim_projection.evidence_refs == ["urn:relay:scripture:evidence:acts-18-2-3"]

    assert [source_bundle_projection, evidence_projection] = manifest.sources
    assert source_bundle_projection.kind == "source_bundle"

    assert source_bundle_projection.source_id ==
             "urn:relay:scripture:source-bundle:ask-aquila-priscilla-1"

    assert {:ok, evidence} =
             RelayMark.Scripture.Evidence.from_manifest_source(evidence_projection)

    assert evidence.evidence_id == "urn:relay:scripture:evidence:acts-18-2-3"
    assert evidence.source_id == "askScriptureRelease1"
    assert evidence.source_revision == release.corpus_release_id
    assert evidence.span.start.book_id == "ACT"
    assert evidence.span.start.chapter == 18
    assert evidence.span.start.verse_label == "2"
    assert evidence.span.end.verse_label == "3"
    assert evidence.release == release
    assert manifest.actions == []
  end

  test "decodes the canonical refused Scripture Ask paper without answer projections" do
    assert {:ok, document} =
             "../../../spec/relaymark/examples/scripture-ask-refused.ast.json"
             |> fixture()
             |> RelayMark.decode_document()

    assert %{
             "profile" => "relaymark.agent_answer.v1",
             "outcome" => "refused",
             "question" => "Was Priscilla the author of Hebrews?",
             "question_id" =>
               "sha256:b776b0f739964c4ebe9826ffef5212952a7a1ec9e90e2ac22f7839ae7ae56052",
             "refusal_reason" => "insufficient_evidence"
           } = document.frontmatter

    assert [heading, explanation] = document.blocks
    assert heading.type == "heading"
    assert RelayMark.Block.plain_text(heading) == "Answer unavailable"
    assert explanation.type == "paragraph"
    assert RelayMark.Block.plain_text(explanation) != ""
    assert document.resources == []

    assert {:ok, manifest} =
             "../../../spec/relaymark/examples/scripture-ask-refused.manifest.json"
             |> fixture()
             |> RelayMark.decode_manifest()

    assert manifest.claims == []
    assert manifest.sources == []
    assert manifest.actions == []
  end

  defp fixture(relative_path) do
    __DIR__
    |> Path.join(relative_path)
    |> Path.expand()
    |> File.read!()
  end
end
