defmodule RelayMark.DocumentRendererTest do
  use ExUnit.Case, async: true

  test "executable authored links fail before static HTML is emitted" do
    assert {:ok, ast} = RelayMark.parse_document("[Evidence](https://example.com)")

    for href <- [
          "javascript:alert(1)",
          "data:text/html,<script>",
          "vbscript:msgbox(1)",
          "//evil.example",
          "https://u:p@example.com"
        ] do
      bad = put_in(ast, ["blocks", Access.at(0), "content", Access.at(0), "href"], href)
      assert {:error, _} = RelayMark.render_document(bad)
    end
  end

  test "nested authored semantics render escaped text without host hydration" do
    ast = %{
      "type" => "relaymark.document",
      "blocks" => [
        %{
          "id" => "b00000000000040008000000000000001",
          "type" => "quote",
          "content" => [
            %{
              "id" => "b00000000000040008000000000000002",
              "type" => "paragraph",
              "content" => [
                %{"type" => "strong", "content" => [%{"type" => "text", "text" => "A < B"}]},
                %{"type" => "hard_break"},
                %{
                  "type" => "link",
                  "href" => "https://example.com/?a=1&b=2",
                  "content" => [%{"type" => "text", "text" => "Evidence"}]
                }
              ]
            }
          ]
        }
      ]
    }

    assert {:ok, html} = RelayMark.render_document(ast)

    assert html ==
             "<blockquote><p><strong>A &lt; B</strong><br><a href=\"https://example.com/?a=1&amp;b=2\" target=\"_blank\" rel=\"noopener noreferrer nofollow\">Evidence</a></p></blockquote>"

    assert {:error, _} =
             RelayMark.render_document(put_in(ast, ["blocks", Access.at(0), "type"], "unknown"))
  end

  test "linked task identity and callout settings hydrate from escaped authored attrs" do
    assert {:ok, ast} =
             RelayMark.parse_document(
               "- [ ] Linked task\n\n@Callout(tone: \"info\", emphasis: \"strong\") {\nNotice\n}"
             )

    ast =
      put_in(
        ast,
        ["blocks", Access.at(0), "content", Access.at(0), "props", "entityId"],
        "11111111-1111-4111-8111-111111111111"
      )

    assert {:ok, html} = RelayMark.render_document(ast)
    assert html =~ "data-relay-task-item=\"11111111-1111-4111-8111-111111111111\""
    assert html =~ "&quot;entityId&quot;:&quot;11111111-1111-4111-8111-111111111111&quot;"
    assert html =~ "&quot;tone&quot;:&quot;info&quot;"
    refute html =~ "relaymarkId"
  end

  test "static tables preserve merged widths and explicit alignment without a host minimum" do
    fixture =
      Path.expand(
        "../../../spec/relaymark/collaboration/fixtures/canonical-table-widths.json",
        __DIR__
      )
      |> File.read!()
      |> Jason.decode!()

    ast = fixture["document"]
    assert {:ok, xml} = RelayMark.DocumentXML.from_document(ast)
    assert {:ok, ^ast} = RelayMark.DocumentXML.to_document(xml)
    assert {:ok, html} = RelayMark.render_document(ast)
    for colgroup <- fixture["expected_colgroups"], do: assert(html =~ colgroup)

    assert html =~
             ~s(<th colspan="2" rowspan="1" colwidth="120,180" data-align="center" style="text-align: center"><p><strong>Title 🌍</strong></p></th>)

    assert html =~
             ~s(<td colspan="1" rowspan="2" colwidth="0" data-align="left" style="text-align: left">)

    refute html =~ "width: 0px"
    refute html =~ "min-width"

    for width <- [[-1, 180], [1.5, 180], [120]] do
      bad =
        put_in(
          ast,
          [
            "blocks",
            Access.at(0),
            "content",
            Access.at(0),
            "content",
            Access.at(0),
            "props",
            "colwidth"
          ],
          width
        )

      assert {:error, _} = RelayMark.render_document(bad)
    end
  end
end
