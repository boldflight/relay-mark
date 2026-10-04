defmodule RelayMark.DocumentXMLTest do
  use ExUnit.Case, async: true
  @fixtures Path.expand("../../../spec/relaymark/collaboration/fixtures", __DIR__)
  test "independent browser fixture meanings and identities survive generic XML construction" do
    files = Path.wildcard(Path.join(@fixtures, "*.json"))

    corpus =
      Enum.flat_map(files, fn path ->
        fixture = path |> File.read!() |> Jason.decode!()
        if fixture["expected_ast"], do: [{path, fixture["expected_ast"]}], else: []
      end)

    assert length(corpus) >= 5

    for {path, ast} <- corpus do
      assert {:ok, snapshot} = RelayMark.DocumentXML.from_document(ast), path
      assert {:ok, ^ast} = RelayMark.DocumentXML.to_document(snapshot), path
    end
  end

  test "rich authorship metadata stays in the same portable document" do
    ast = %{
      "type" => "relaymark.document",
      "frontmatter" => %{"title" => "Keep source"},
      "meta" => %{"import" => "original"},
      "blocks" => [
        %{
          "id" => "b00000000000040008000000000000001",
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Exact 🌍 text"}]
        }
      ]
    }

    assert {:ok, snapshot} = RelayMark.DocumentXML.from_document(ast)
    assert snapshot["metadata"] == Map.take(ast, ~w(frontmatter meta))
    assert {:ok, ^ast} = RelayMark.DocumentXML.to_document(snapshot)
    assert {:error, _} = RelayMark.DocumentXML.to_document(Map.put(snapshot, "unknown", true))
    bad = put_in(snapshot, ["metadata", "permissions"], %{"write" => true})
    assert {:error, _} = RelayMark.DocumentXML.to_document(bad)
  end

  test "unknown nodes and copied block identities fail before construction" do
    ast = %{
      "type" => "relaymark.document",
      "blocks" => [
        %{"id" => "b00000000000040008000000000000001", "type" => "paragraph", "content" => []}
      ]
    }

    assert {:ok, snapshot} = RelayMark.DocumentXML.from_document(ast)

    assert {:error, _} =
             RelayMark.DocumentXML.to_document(Map.update!(snapshot, "children", &(&1 ++ &1)))

    assert {:error, _} =
             RelayMark.DocumentXML.to_document(
               put_in(snapshot, ["children", Access.at(0), "name"], "unknown")
             )
  end
end
