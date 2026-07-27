defmodule RelayMarkAgentAnswerTest do
  use ExUnit.Case, async: true

  @receipt_path Path.expand(
                  "../../../spec/relaymark/conformance/agent-answer-fixture-receipt.json",
                  __DIR__
                )

  test "accepts the exact receipted Agent Answer bytes and canonical manifest pairs" do
    receipt = decode_file(@receipt_path)
    receipt_directory = Path.dirname(@receipt_path)

    assert receipt["type"] == "relaymark.fixture_receipt"
    assert receipt["version"] == "0.5.0-draft"
    assert receipt["algorithm"] == "sha256"

    for pair_receipt <- receipt["pairs"] do
      document_json = read_relative(receipt_directory, pair_receipt["document"]["path"])
      manifest_json = read_relative(receipt_directory, pair_receipt["manifest"]["path"])

      assert sha256(document_json) == pair_receipt["document"]["sha256"]
      assert sha256(manifest_json) == pair_receipt["manifest"]["sha256"]

      assert {:ok, pair} =
               RelayMark.validate_transported_agent_answer_pair(
                 document_json,
                 manifest_json,
                 %{"surface" => "scripture_ask"}
               )

      assert pair.document.frontmatter["profile"] == "relaymark.agent_answer.v1"
      assert pair.manifest.actions == []
      assert pair.document_digest == "sha256:" <> pair_receipt["document"]["sha256"]
      assert pair.manifest_digest == "sha256:" <> pair_receipt["manifest"]["sha256"]
    end
  end

  test "rejects non-portable transported JSON and accepts escaped scalar pairs" do
    document_json = fixture("scripture-ask-refused.ast.json")
    manifest_json = fixture("scripture-ask-refused.manifest.json")

    invalid_utf8 =
      :binary.replace(
        document_json,
        "Answer unavailable",
        <<"Answer ", 0xFF, "unavailable">>,
        [:global]
      )

    assert_transport_document_json_error(invalid_utf8, manifest_json)

    raw_control =
      :binary.replace(
        document_json,
        "Answer unavailable",
        "Answer\nunavailable",
        [:global]
      )

    assert_transport_document_json_error(raw_control, manifest_json)

    lone_surrogate =
      :binary.replace(
        document_json,
        "Answer unavailable",
        "\\uD83D",
        [:global]
      )

    assert_transport_document_json_error(lone_surrogate, manifest_json)

    escaped_scalar_pair =
      document_json
      |> decode()
      |> put_in(["frontmatter", "title"], "😀")
      |> Jason.encode!()
      |> String.replace("😀", "\\uD83D\\uDE00")

    assert {:ok, pair} =
             RelayMark.validate_transported_agent_answer_pair(
               escaped_scalar_pair,
               manifest_json
             )

    assert pair.document.frontmatter["title"] == "😀"
  end

  test "normalizes transported document schema failures across adapters" do
    invalid_document =
      "scripture-ask-refused.ast.json"
      |> decode_fixture()
      |> put_in(["blocks", Access.at(0), "id"], "1-invalid")

    manifest_json = fixture("scripture-ask-refused.manifest.json")

    for document <- [
          update_in(invalid_document["frontmatter"], &Map.delete(&1, "profile")),
          put_in(invalid_document, ["frontmatter", "profile"], "relaymark.wrong_profile.v1")
        ] do
      assert {:error,
              [
                %{
                  "level" => "error",
                  "code" => "relaymark.schema.invalid",
                  "message" => "Document does not conform to the RelayMark document schema."
                }
              ]} =
               RelayMark.validate_transported_agent_answer_pair(
                 Jason.encode!(document),
                 manifest_json
               )
    end
  end

  test "rejects action and content drift from the transported canonical projection" do
    refused_document =
      fixture("scripture-ask-refused.ast.json")

    action_drift =
      fixture("invalid-agent-answer-manifest-action.manifest.json")

    expected =
      decode_fixture("invalid-agent-answer-manifest-action.diagnostics.json")

    assert {:error, ^expected} =
             RelayMark.validate_transported_agent_answer_pair(
               refused_document,
               action_drift,
               %{"surface" => "scripture_ask"}
             )

    answered_document =
      fixture("scripture-ask-answered.ast.json")

    content_drift =
      "scripture-ask-answered.manifest.json"
      |> decode_fixture()
      |> put_in(["claims", Access.at(0), "text"], "A forged answer.")
      |> Jason.encode!()

    assert {:error, ^expected} =
             RelayMark.validate_transported_agent_answer_pair(
               answered_document,
               content_drift,
               %{"surface" => "scripture_ask"}
             )
  end

  test "requires Scripture evidence only for explicit Scripture Ask host context" do
    document = decode_fixture("invalid-agent-answer-scripture-evidence.ast.json")
    expected = decode_fixture("invalid-agent-answer-scripture-evidence.diagnostics.json")

    assert :ok = RelayMark.validate_document(document)

    assert {:error, ^expected} =
             RelayMark.validate_document(document, %{"surface" => "scripture_ask"})

    combined_invalid =
      document
      |> put_in(["blocks", Access.at(1), "props", "status"], "disputed")
      |> update_in(["blocks", Access.at(1), "evidence_refs"], &(&1 ++ [hd(&1)]))

    assert {:error, diagnostics} =
             RelayMark.validate_document(combined_invalid, %{"surface" => "scripture_ask"})

    assert Enum.map(diagnostics, & &1["code"]) == [
             "relaymark.agent_answer.claim",
             "relaymark.agent_answer.claim_evidence",
             "relaymark.agent_answer.scripture_evidence"
           ]
  end

  defp fixture(name) do
    Path.expand("../../../spec/relaymark/examples/#{name}", __DIR__)
    |> File.read!()
  end

  defp decode_fixture(name), do: name |> fixture() |> decode()
  defp decode_file(path), do: path |> File.read!() |> decode()

  defp decode(json) do
    {:ok, value} = RelayMark.JSON.decode(json)
    value
  end

  defp read_relative(directory, path) do
    directory
    |> Path.join(path)
    |> Path.expand()
    |> File.read!()
  end

  defp sha256(bytes) do
    :crypto.hash(:sha256, bytes)
    |> Base.encode16(case: :lower)
  end

  defp assert_transport_document_json_error(document_json, manifest_json) do
    assert {:error,
            [
              %{
                "level" => "error",
                "code" => "relaymark.transport.document_json",
                "message" => "Transported RelayMark document must be valid UTF-8 JSON."
              }
            ]} =
             RelayMark.validate_transported_agent_answer_pair(
               document_json,
               manifest_json
             )
  end
end
