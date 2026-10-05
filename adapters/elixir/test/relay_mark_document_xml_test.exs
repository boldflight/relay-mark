defmodule RelayMark.DocumentXMLTest do
  use ExUnit.Case, async: true
  @fixtures Path.expand("../../../spec/relaymark/collaboration/fixtures", __DIR__)
  test "canonical video rejects legacy derived attrs and finite import records their removal" do
    fixture =
      Path.expand(
        "../../../spec/relaymark/collaboration/fixtures/rich-video-v3-draft.json",
        __DIR__
      )
      |> File.read!()
      |> Jason.decode!()

    assert {:error, _} = RelayMark.DocumentXML.to_document(fixture["xml"])

    assert {:ok, converted} =
             RelayMark.import_document_snapshot(fixture["xml"], namespace: "retained-video")

    assert converted["document"] == Map.delete(fixture["expected_ast"], "version")

    assert Enum.at(converted["snapshot"]["children"], 1)["attributes"] == %{
             "relaymarkId" => "b28718f2e96f1458d9608c7222745fbc0",
             "videoId" => "11111111-1111-4111-8111-111111111111"
           }

    assert converted["normalizations"] == [
             %{
               "path" => [1],
               "operation" => "remove_attribute",
               "name" => "source",
               "before" => "mux"
             },
             %{
               "path" => [1],
               "operation" => "remove_attribute",
               "name" => "status",
               "before" => "ready"
             }
           ]

    nondefault =
      put_in(fixture, ["xml", "children", Access.at(1), "attributes", "source"], "youtube")

    assert {:error, _} =
             RelayMark.import_document_snapshot(nondefault["xml"], namespace: "retained-video")
  end

  test "finite atom normalization removes only recorded null presentation fields" do
    {:ok, document} =
      RelayMark.parse_document(
        "[[Person: 11111111-1111-4111-8111-111111111111 | Full title]] and [[Tag: aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa | #followup]]",
        namespace: "retained-atoms"
      )

    {:ok, snapshot} = RelayMark.DocumentXML.from_document(document)

    old =
      snapshot
      |> put_in(["children", Access.at(0), "children", Access.at(0), "attributes", "status"], nil)
      |> put_in(
        ["children", Access.at(0), "children", Access.at(0), "attributes", "subtitle"],
        nil
      )
      |> put_in(["children", Access.at(0), "children", Access.at(2), "attributes", "color"], nil)

    assert {:ok, imported} = RelayMark.import_document_snapshot(old, namespace: "retained-atoms")
    assert imported["snapshot"] == snapshot
    assert imported["document"] == document

    assert imported["normalizations"] == [
             %{
               "path" => [0, 0],
               "operation" => "remove_attribute",
               "name" => "status",
               "before" => nil
             },
             %{
               "path" => [0, 0],
               "operation" => "remove_attribute",
               "name" => "subtitle",
               "before" => nil
             },
             %{
               "path" => [0, 2],
               "operation" => "remove_attribute",
               "name" => "color",
               "before" => nil
             }
           ]

    nondefault =
      put_in(
        old,
        ["children", Access.at(0), "children", Access.at(0), "attributes", "status"],
        "resolved"
      )

    assert {:error, _} =
             RelayMark.import_document_snapshot(nondefault, namespace: "retained-atoms")
  end

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

  test "actual browser XML video defaults and Yex whole-number attributes retain authored meaning" do
    fixture = Path.join(@fixtures, "rich-video-v3-draft.json") |> File.read!() |> Jason.decode!()

    assert {:ok, migrated} =
             RelayMark.import_document_snapshot(fixture["xml"],
               namespace: "browser-video-defaults"
             )

    assert migrated["document"] == fixture["expected_ast"]

    ast = %{
      "type" => "relaymark.document",
      "blocks" => [
        %{
          "id" => "b00000000000040008000000000000001",
          "type" => "table",
          "content" => [
            %{
              "id" => "b00000000000040008000000000000002",
              "type" => "table_row",
              "content" => [
                %{
                  "id" => "b00000000000040008000000000000003",
                  "type" => "table_cell",
                  "props" => %{
                    "header" => true,
                    "colspan" => 1,
                    "rowspan" => 1,
                    "colwidth" => [120],
                    "align" => nil
                  },
                  "content" => [
                    %{
                      "id" => "b00000000000040008000000000000004",
                      "type" => "paragraph",
                      "content" => [%{"type" => "text", "text" => "Cell"}]
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }

    assert {:ok, snapshot} = RelayMark.DocumentXML.from_document(ast)
    floated = whole_numbers(snapshot)
    assert RelayMark.DocumentXML.to_document(floated) == {:ok, ast}
    first = hd(snapshot["children"])

    bad = %{
      snapshot
      | "children" => [Map.put(first, "attributes", %{}) | tl(snapshot["children"])]
    }

    assert {:error, [diagnostic]} = RelayMark.DocumentXML.to_document(bad)
    assert diagnostic["reason"] == ":block_identity"
  end

  defp whole_numbers(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {k, whole_numbers(v)} end)

  defp whole_numbers(value) when is_list(value), do: Enum.map(value, &whole_numbers/1)
  defp whole_numbers(value) when is_integer(value), do: value * 1.0
  defp whole_numbers(value), do: value

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

    empty =
      Map.merge(ast, %{
        "frontmatter" => %{},
        "annotations" => [],
        "resources" => [],
        "meta" => %{}
      })

    assert {:ok, empty_snapshot} = RelayMark.DocumentXML.from_document(empty)

    assert empty_snapshot["metadata"] ==
             Map.take(empty, ~w(frontmatter annotations resources meta))

    assert {:ok, ^empty} = RelayMark.DocumentXML.to_document(empty_snapshot)
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

  test "identified generic directives retain rich text, table children and metadata" do
    ast =
      Path.expand(
        "../../../spec/relaymark/collaboration/fixtures/canonical-directives.json",
        __DIR__
      )
      |> File.read!()
      |> Jason.decode!()

    assert {:ok, snapshot} = RelayMark.DocumentXML.from_document(ast)

    assert Enum.map(snapshot["children"], & &1["name"]) == [
             "relayEvidence",
             "relayClaim",
             "relayComparison"
           ]

    assert {:ok, ^ast} = RelayMark.DocumentXML.to_document(snapshot)
    assert {:ok, html} = RelayMark.render_document(ast)
    assert html =~ "<strong>Résumé 世界</strong>"
    assert html =~ "<table>"
  end

  test "CRDT split runs project one canonical equal-mark text without changing inline boundaries" do
    id = "b00000000000040008000000000000001"

    snapshot = %{
      "kind" => "fragment",
      "children" => [
        %{
          "kind" => "element",
          "name" => "paragraph",
          "attributes" => %{"relaymarkId" => id},
          "children" => [
            %{"kind" => "text", "delta" => [%{"insert" => "A"}, %{"insert" => "🌍Z"}]},
            %{
              "kind" => "text",
              "delta" => [
                %{"insert" => "B", "attributes" => %{"bold" => %{}}},
                %{"insert" => "C", "attributes" => %{"bold" => %{}}}
              ]
            },
            %{"kind" => "element", "name" => "hardBreak", "attributes" => %{}, "children" => []},
            %{"kind" => "text", "delta" => [%{"insert" => "D", "attributes" => %{"bold" => %{}}}]}
          ]
        }
      ]
    }

    expected = %{
      "type" => "relaymark.document",
      "blocks" => [
        %{
          "id" => id,
          "type" => "paragraph",
          "content" => [
            %{"type" => "text", "text" => "A🌍Z"},
            %{"type" => "strong", "content" => [%{"type" => "text", "text" => "BC"}]},
            %{"type" => "hard_break"},
            %{"type" => "strong", "content" => [%{"type" => "text", "text" => "D"}]}
          ]
        }
      ]
    }

    assert RelayMark.DocumentXML.to_document(snapshot) == {:ok, expected}
  end
end
