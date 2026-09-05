defmodule RelayMark.CollaborativeProseTest do
  use ExUnit.Case, async: true

  alias RelayMark.CollaborativeProse

  test "projects Unicode and canonical entity links without treating text as syntax" do
    nodes = [
      %{
        "tag" => "paragraph",
        "attributes" => %{},
        "children" => [
          %{
            "delta" => [
              %{"insert" => "Hello 🌍 [literal] ", "attributes" => %{}},
              %{
                "insert" => "friend",
                "attributes" => %{"bold" => %{}, "link" => %{"href" => "relay:entity/123"}}
              }
            ]
          }
        ]
      }
    ]

    assert {:ok, source} = CollaborativeProse.to_markdown(nodes)
    assert source == "Hello 🌍 \\[literal\\] [**friend**](<relay:entity/123>)"
  end

  test "refuses unknown structure and marks instead of producing lossy source" do
    assert {:error, {:unsupported_collaboration_content, {:node, "privateLayer"}}} =
             CollaborativeProse.to_markdown([
               %{"tag" => "privateLayer", "attributes" => %{}, "children" => []}
             ])

    assert {:error, {:unsupported_collaboration_content, :attributes}} =
             CollaborativeProse.to_markdown([
               %{
                 "tag" => "paragraph",
                 "attributes" => %{},
                 "children" => [
                   %{"delta" => [%{"insert" => "secret", "attributes" => %{"unknown" => true}}]}
                 ]
               }
             ])
  end

  test "code fences preserve content and refuse ambiguous delimiters" do
    node = %{
      "tag" => "codeBlock",
      "attributes" => %{"language" => "swift"},
      "children" => [
        %{"delta" => [%{"insert" => "let x = 1"}]}
      ]
    }

    assert {:ok, "```swift\nlet x = 1\n```"} = CollaborativeProse.to_markdown([node])
  end
end
