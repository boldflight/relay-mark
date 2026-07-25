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
