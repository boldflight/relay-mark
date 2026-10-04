defmodule RelayMark.FormPublicationImportTest do
  use ExUnit.Case, async: true
  @root Path.expand("../../../spec/relaymark/collaboration/fixtures", __DIR__)
  defp fixture(name), do: File.read!(Path.join(@root, name)) |> Jason.decode!()

  test "canonical saved publication keeps exact document identities without projected-block conversion" do
    publication = fixture("historical-form-publication.json")
    expected = fixture("form-publication-import-expected.json")

    current =
      publication
      |> Map.put("document", expected["document"])
      |> Map.put("blocks", [
        %{
          "id" => "domain-projected-prose",
          "type" => "paragraph",
          "label" => "derived",
          "settings" => %{"projection" => true}
        }
      ])

    assert {:ok, result} =
             RelayMark.import_form_publication(current, namespace: "different-rerun-namespace")

    assert result.document == expected["document"]
    assert result.normalizations == []
    assert result.identity_mapping["added"] == []
    assert result.identity_mapping["remapped"] == []
    assert Enum.at(result.document["blocks"], 2)["id"] in result.identity_mapping["retained"]

    assert {:ok, exact_source} = RelayMark.serialize_document(result.document)

    assert {:ok, ^result} =
             RelayMark.import_form_publication(current,
               namespace: "different-rerun-namespace",
               source: exact_source
             )

    assert {:error, _} =
             RelayMark.import_form_publication(current,
               namespace: "different-rerun-namespace",
               source: "Changed release prose"
             )

    malformed =
      put_in(
        current,
        ["document", "blocks", Access.at(0), "content", Access.at(0), "type"],
        "unsupported"
      )

    assert {:error, _} =
             RelayMark.import_form_publication(malformed, namespace: "different-rerun-namespace")
  end

  test "saved published quiz keeps rich prose, field/choice identities and exact answer key" do
    publication = fixture("historical-form-publication.json")
    expected = fixture("form-publication-import-expected.json")

    assert {:ok, result} =
             RelayMark.import_form_publication(publication, namespace: "publication-proof")

    assert result.document == expected["document"]
    assert result.identity_mapping == expected["identity_mapping"]
    assert result.normalizations == expected["normalizations"]

    assert Enum.map(result.document["blocks"], & &1["type"]) ==
             ~w(paragraph relay.callout relay.form_question paragraph)

    question = Enum.at(result.document["blocks"], 2)

    assert question["props"]["settings"]["answer_key"] == %{
             "points" => 5,
             "correct_answer" => "correct-bold-answer"
           }

    assert Enum.map(tl(question["content"]), & &1["props"]["id"]) ==
             ~w(correct-bold-answer other-answer)

    conflict =
      put_in(
        publication,
        ["blocks", Access.at(1), "answer_key", "correct_answer"],
        "other-answer"
      )

    assert {:error, _} =
             RelayMark.import_form_publication(conflict, namespace: "publication-proof")

    rich = put_in(publication, ["blocks", Access.at(1), "label"], "First\n\nSecond")
    assert {:error, _} = RelayMark.import_form_publication(rich, namespace: "publication-proof")
  end

  test "only the same retained release source can recover missing published settings" do
    publication = fixture("historical-form-publication.json")
    retained = fixture("form-publication-retained-source.json")

    assert {:ok, result} =
             RelayMark.import_form_publication(publication,
               namespace: "publication-proof",
               source: retained["source"]
             )

    assert result.document == retained["expected"]["document"]
    assert result.identity_mapping == retained["expected"]["identity_mapping"]
    assert result.normalizations == retained["expected"]["normalizations"]

    assert Enum.at(result.document["blocks"], 2)["props"]["settings"]["placeholder"] ==
             "Retained label hint"

    conflicting =
      put_in(publication, ["blocks", Access.at(1), "settings"], %{"placeholder" => "Other hint"})

    assert {:error, _} =
             RelayMark.import_form_publication(conflicting,
               namespace: "publication-proof",
               source: retained["source"]
             )

    assert {:error, _} =
             RelayMark.import_form_publication(publication,
               namespace: "publication-proof",
               source: String.replace(retained["source"], "Choose **one**", "Changed draft label")
             )
  end
end
