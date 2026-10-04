defmodule RelayMark.DocumentRendererTest do
  use ExUnit.Case, async: true

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
end
