defmodule RelayMark.FileProjectionTest do
  use ExUnit.Case, async: true

  test "File projection retains an independently authored descriptor and marked prose" do
    file_id = "11111111-1111-4111-8111-111111111111"

    authored = %{
      "type" => "relaymark.document",
      "blocks" => [
        %{
          "id" => "b00000000000040008000000000000061",
          "type" => "relay.file_ref",
          "props" => %{
            "id" => file_id,
            "uri" => "/m/" <> file_id,
            "label" => "Care Ω.pdf",
            "scope" => "private"
          },
          "content" => []
        },
        %{
          "id" => "b00000000000040008000000000000062",
          "type" => "paragraph",
          "content" => [
            %{"type" => "strong", "content" => [%{"type" => "text", "text" => "Keep 世界"}]},
            %{"type" => "text", "text" => " beside the file."}
          ]
        }
      ]
    }

    expected =
      "@FileRef(id: \"11111111-1111-4111-8111-111111111111\", label: \"Care Ω.pdf\", " <>
        "scope: \"private\", uri: \"/m/11111111-1111-4111-8111-111111111111\") {\n\n}\n\n" <>
        "**Keep 世界** beside the file.\n"

    assert {:ok, projected} = RelayMark.project_document_markdown(authored)
    assert projected == expected
    # Readable Markdown is derived; the exact canonical interchange retains IDs.
    assert {:ok, canonical_source} = RelayMark.serialize_document(authored)
    assert {:ok, ^authored} = RelayMark.parse_document(canonical_source)
  end
end
