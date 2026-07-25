defmodule RelayMarkValidatorTest do
  use ExUnit.Case, async: true

  alias RelayMark.{Schema, ValidationError}

  @valid_fixtures [
    "mentor-meeting.ast.json",
    "agent-paper-review.ast.json",
    "product-research.ast.json",
    "scripture-evidence.ast.json",
    "scripture-ask-answered.ast.json",
    "scripture-ask-refused.ast.json"
  ]

  test "accepts every valid canonical AST conformance fixture" do
    for fixture_name <- @valid_fixtures do
      document = decode_fixture(fixture_name)

      assert :ok = RelayMark.validate_document(document), fixture_name
      assert document == RelayMark.validate_document!(document)
    end
  end

  test "matches the reference runtime identity-collision diagnostics exactly" do
    document = decode_fixture("invalid-identity-collisions.ast.json")
    expected = decode_fixture("invalid-identity-collisions.diagnostics.json")

    assert {:error, ^expected} = RelayMark.validate_document(document)
    assert Enum.all?(expected, &(Schema.validate_diagnostic_schema(&1) == :ok))
  end

  test "matches the reference runtime Agent Answer diagnostics exactly" do
    for fixture_name <- [
          "invalid-agent-answer-question-id",
          "invalid-agent-answer-refusal"
        ] do
      document = decode_fixture("#{fixture_name}.ast.json")
      expected = decode_fixture("#{fixture_name}.diagnostics.json")

      assert {:error, ^expected} = RelayMark.validate_document(document), fixture_name
      assert Enum.all?(expected, &(Schema.validate_diagnostic_schema(&1) == :ok))
    end
  end

  test "ports answered and refused Agent Answer profile semantics" do
    answered = decode_fixture("scripture-ask-answered.ast.json")
    refused = decode_fixture("scripture-ask-refused.ast.json")

    invalid_claim =
      update_block(answered, 1, fn block ->
        put_in(block, ["props", "status"], "disputed")
      end)

    assert diagnostic_codes(invalid_claim) == ["relaymark.agent_answer.claim"]

    duplicate_claim_evidence =
      update_block(answered, 1, fn block ->
        update_in(block["evidence_refs"], &(&1 ++ [hd(&1)]))
      end)

    assert diagnostic_codes(duplicate_claim_evidence) == [
             "relaymark.agent_answer.claim_evidence"
           ]

    invalid_answered_structure =
      update_block(answered, 2, fn block ->
        put_in(block, ["content", Access.at(0), "text"], " Evidence")
      end)

    assert diagnostic_codes(invalid_answered_structure) == [
             "relaymark.agent_answer.answered_structure"
           ]

    second_answer_heading =
      update_in(answered["blocks"], fn blocks ->
        blocks ++
          [
            %{
              "id" => "secondAnswerHeading",
              "type" => "heading",
              "props" => %{"level" => 1},
              "content" => [%{"type" => "text", "text" => "Second answer"}]
            }
          ]
      end)

    assert diagnostic_codes(second_answer_heading) == [
             "relaymark.agent_answer.answered_structure"
           ]

    nested_evidence_heading =
      update_in(answered, ["blocks", Access.at(3), "content"], fn content ->
        content ++
          [
            %{
              "id" => "nestedEvidenceHeading",
              "type" => "heading",
              "props" => %{"level" => 2},
              "content" => [%{"type" => "text", "text" => "Nested heading"}]
            }
          ]
      end)

    assert diagnostic_codes(nested_evidence_heading) == [
             "relaymark.agent_answer.answered_structure"
           ]

    integral_heading_levels =
      answered
      |> update_block(0, &put_in(&1, ["props", "level"], 1.0))
      |> update_block(2, &put_in(&1, ["props", "level"], 2.0))

    assert :ok = RelayMark.validate_document(integral_heading_levels)

    duplicated_concrete_evidence =
      update_in(answered, ["blocks", Access.at(3), "content"], fn content ->
        duplicate =
          content
          |> hd()
          |> Map.put("id", "askEvidenceDuplicate")

        content ++ [duplicate]
      end)

    assert diagnostic_codes(duplicated_concrete_evidence) == [
             "relaymark.agent_answer.claim_evidence",
             "relaymark.identity.duplicate_evidence"
           ]

    non_concrete_evidence_target =
      put_in(
        answered,
        ["blocks", Access.at(1), "evidence_refs"],
        [get_in(answered, ["blocks", Access.at(3), "props", "id"])]
      )

    assert diagnostic_codes(non_concrete_evidence_target) == [
             "relaymark.agent_answer.claim_evidence"
           ]

    exact_question =
      answered
      |> put_in(["frontmatter", "question"], "  Why did Priscilla travel? 🌿\n")
      |> put_in(
        ["frontmatter", "question_id"],
        "sha256:4028e93caf14fa131e71f9a4983efc2dcca8f1220d2e58e0deb386cb6e33ed23"
      )

    assert :ok = RelayMark.validate_document(exact_question)

    unicode_whitespace_title = put_in(answered, ["frontmatter", "title"], "\u{0085}")
    assert diagnostic_codes(unicode_whitespace_title) == ["relaymark.agent_answer.title"]

    unicode_whitespace_claim =
      put_in(answered, ["blocks", Access.at(1), "content", Access.at(0), "text"], "\u{0085}")

    assert diagnostic_codes(unicode_whitespace_claim) == ["relaymark.agent_answer.claim"]

    unicode_whitespace_explanation =
      put_in(refused, ["blocks", Access.at(1), "content", Access.at(0), "text"], "\u{0085}")

    assert diagnostic_codes(unicode_whitespace_explanation) == [
             "relaymark.agent_answer.refused_structure"
           ]

    unicode_whitespace_evidence_reference =
      put_in(answered, ["blocks", Access.at(1), "evidence_refs"], ["\u{0085}"])

    assert diagnostic_codes(unicode_whitespace_evidence_reference) == [
             "relaymark.policy.evidence_required",
             "relaymark.evidence.invalid_reference",
             "relaymark.agent_answer.claim_evidence"
           ]

    byte_order_mark_title = put_in(answered, ["frontmatter", "title"], "\u{FEFF}")
    assert :ok = RelayMark.validate_document(byte_order_mark_title)

    byte_order_mark_evidence_reference =
      put_in(answered, ["blocks", Access.at(1), "evidence_refs"], ["\u{FEFF}"])

    assert diagnostic_codes(byte_order_mark_evidence_reference) == [
             "relaymark.evidence.unresolved_reference",
             "relaymark.agent_answer.claim_evidence"
           ]

    answered_with_refusal_reason =
      put_in(answered, ["frontmatter", "refusal_reason"], "insufficient_evidence")

    assert diagnostic_codes(answered_with_refusal_reason) == [
             "relaymark.agent_answer.refusal_reason"
           ]

    invalid_refusal =
      refused
      |> put_in(["frontmatter", "refusal_reason"], "provider_failure")
      |> update_in(["blocks"], fn blocks ->
        blocks ++
          [
            %{
              "id" => "forbiddenRefusalSource",
              "type" => "relay.source_bundle",
              "props" => %{"id" => "forbidden-refusal-source"},
              "content" => []
            }
          ]
      end)

    assert diagnostic_codes(invalid_refusal) == [
             "relaymark.agent_answer.refusal_reason",
             "relaymark.agent_answer.refused_structure",
             "relaymark.agent_answer.refused_content"
           ]

    inexact_refusal_heading =
      update_block(refused, 0, fn block ->
        put_in(block, ["content", Access.at(0), "text"], "Answer unavailable ")
      end)

    assert diagnostic_codes(inexact_refusal_heading) == [
             "relaymark.agent_answer.refused_structure"
           ]

    for {field, value, expected_code} <- [
          {"title", "", "relaymark.agent_answer.title"},
          {"scope", "team", "relaymark.agent_answer.scope"},
          {"question", "", "relaymark.agent_answer.question"},
          {"outcome", "partial", "relaymark.agent_answer.outcome"}
        ] do
      invalid_frontmatter = put_in(answered, ["frontmatter", field], value)
      assert diagnostic_codes(invalid_frontmatter) == [expected_code], field
    end
  end

  test "reports JSON Schema 2020-12 structural failures as portable diagnostics" do
    invalid_documents = [
      %{
        "type" => "relaymark.document",
        "version" => 1,
        "blocks" => [],
        "unexpected" => true
      },
      document([
        %{"id" => "1-invalid", "type" => "paragraph"}
      ]),
      document([
        %{"id" => "b1", "type" => "relay.source_bundle", "props" => %{}}
      ])
    ]

    for invalid_document <- invalid_documents do
      assert {:error, [diagnostic]} = RelayMark.validate_document(invalid_document)
      assert diagnostic["code"] == "relaymark.schema.invalid"
      assert diagnostic["level"] == "error"
      assert is_binary(diagnostic["path"])
      assert :ok = Schema.validate_diagnostic_schema(diagnostic)
    end
  end

  test "reports unknown directives and unresolved evidence with reference-runtime messages" do
    unknown_directive =
      document([
        %{"id" => "b1", "type" => "relay.unknown", "props" => %{}}
      ])

    assert {:error,
            [
              %{
                "level" => "error",
                "code" => "relaymark.directive.unknown_type",
                "message" => "Unknown Relay block type 'relay.unknown'."
              }
            ]} = RelayMark.validate_document(unknown_directive)

    unresolved_claim =
      document([
        %{
          "id" => "b1",
          "type" => "relay.claim",
          "props" => %{"key" => "processor.speed", "evidence" => ["missing-source"]}
        }
      ])

    assert {:error,
            [
              %{
                "level" => "error",
                "code" => "relaymark.evidence.unresolved_reference",
                "message" => "relay.claim evidence reference 'missing-source' does not resolve."
              }
            ]} = RelayMark.validate_document(unresolved_claim)
  end

  test "ports directive attribute and action lifecycle semantic rules" do
    invalid_action =
      document([
        %{
          "id" => "b1",
          "type" => "relay.action_row",
          "props" => %{
            "proposal_id" => "proposal-1",
            "proposal_record_id" => "proposal-1",
            "proposal_revision" => 0,
            "action" => "relay.task.create",
            "review" => "accepted",
            "decision_id" => "",
            "execution_id" => nil,
            "undo_id" => "undo-1"
          }
        }
      ])

    assert {:error, diagnostics} = RelayMark.validate_document(invalid_action)

    assert Enum.map(diagnostics, & &1["code"]) == [
             "relaymark.attribute.string",
             "relaymark.action.proposal_identity",
             "relaymark.action.proposal_revision",
             "relaymark.action.lifecycle_id",
             "relaymark.action.lifecycle_id",
             "relaymark.action.lifecycle_state"
           ]

    assert Enum.all?(diagnostics, &(Schema.validate_diagnostic_schema(&1) == :ok))
  end

  test "ports claim and comparison semantic rules" do
    invalid_research =
      document([
        %{
          "id" => "b1",
          "type" => "relay.claim",
          "props" => %{
            "key" => "processor.speed",
            "confidence" => 1.1,
            "evidence" => ["b1"]
          }
        },
        %{
          "id" => "b2",
          "type" => "relay.comparison",
          "props" => %{
            "subjects" => ["subject-a", "subject-b"],
            "criteria" => ["speed"],
            "values" => %{"speed" => %{"subject-a" => 10}},
            "preferred" => "subject-c",
            "evidence" => ["b1"]
          }
        }
      ])

    assert {:error, diagnostics} = RelayMark.validate_document(invalid_research)

    assert Enum.map(diagnostics, & &1["code"]) == [
             "relaymark.claim.confidence_range",
             "relaymark.comparison.preferred",
             "relaymark.comparison.values_coverage"
           ]
  end

  test "decodes the portable Scripture evidence fixture into typed adapters" do
    document =
      "scripture-evidence.ast.json"
      |> decode_fixture()
      |> RelayMark.Document.from_map()

    assert {:ok, release} =
             document.resources
             |> hd()
             |> RelayMark.Resource.scripture_release()

    assert release.translation_id == "urn:relay:scripture:translation:kjv"
    assert release.corpus_release_id == "urn:relay:scripture:corpus:kjv:1769-fixture-1"

    manifest =
      "scripture-evidence.manifest.json"
      |> decode_fixture()
      |> RelayMark.Manifest.from_map()

    assert {:ok, evidence} =
             manifest.sources
             |> hd()
             |> RelayMark.Scripture.Evidence.from_manifest_source()

    assert evidence.source_revision == release.corpus_release_id
    assert evidence.span.start.kind == :chapter
    assert evidence.span.start.verse_label == "2"
    assert evidence.span.end.verse_label == "3"

    assert %RelayMark.Scripture.Coordinate{
             kind: :section,
             section_id: "prologue",
             verse_label: "prologue"
           } =
             RelayMark.Scripture.Coordinate.from_map(%{
               "book_id" => "SIR",
               "coordinate_kind" => "section",
               "section_id" => "prologue",
               "verse_label" => "prologue"
             })
  end

  test "bang validation raises with the same diagnostics" do
    invalid_document = document([%{"id" => "b1", "type" => "relay.unknown"}])

    assert {:error, diagnostics} = RelayMark.validate_document(invalid_document)

    exception =
      assert_raise ValidationError, fn ->
        RelayMark.validate_document!(invalid_document)
      end

    assert exception.diagnostics == diagnostics

    assert Exception.message(exception) ==
             "RelayMark document validation failed with 1 diagnostic(s)."
  end

  defp document(blocks) do
    %{"type" => "relaymark.document", "version" => 1, "blocks" => blocks}
  end

  defp diagnostic_codes(document) do
    assert {:error, diagnostics} = RelayMark.validate_document(document)
    Enum.map(diagnostics, & &1["code"])
  end

  defp update_block(document, index, update) do
    update_in(document["blocks"], &List.update_at(&1, index, update))
  end

  defp decode_fixture(name) do
    path =
      __DIR__
      |> Path.join("../../../spec/relaymark/examples")
      |> Path.join(name)
      |> Path.expand()

    {:ok, value} = path |> File.read!() |> RelayMark.JSON.decode()
    value
  end
end
