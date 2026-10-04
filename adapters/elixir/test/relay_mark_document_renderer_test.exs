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
end
