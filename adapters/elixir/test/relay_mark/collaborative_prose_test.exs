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

  test "code fences preserve content" do
    node = %{
      "tag" => "codeBlock",
      "attributes" => %{"language" => "swift"},
      "children" => [
        %{"delta" => [%{"insert" => "let x = 1"}]}
      ]
    }

    assert {:ok, "```swift\nlet x = 1\n```"} = CollaborativeProse.to_markdown([node])
  end

  test "code spans choose lossless delimiters and CommonMark padding" do
    for {text, expected} <- [
          {"a`b", "``a`b``"},
          {"`", "`` ` ``"},
          {"``x`", "``` ``x` ```"},
          {" padded ", "`  padded  `"},
          {"  ", "`  `"},
          {" left", "` left`"},
          {"right ", "`right `"}
        ] do
      node = %{
        "tag" => "paragraph",
        "attributes" => %{},
        "children" => [
          %{"delta" => [%{"insert" => text, "attributes" => %{"code" => %{}}}]}
        ]
      }

      assert {:ok, ^expected} = CollaborativeProse.to_markdown([node])
    end
  end

  test "arbitrarily long mixed fences and trailing newlines stay literal" do
    text = "```\n~~~~\n``````\n"

    node = %{
      "tag" => "codeBlock",
      "attributes" => %{"language" => "swift"},
      "children" => [%{"delta" => [%{"insert" => text}]}]
    }

    assert {:ok, "```````swift\n" <> rest} = CollaborativeProse.to_markdown([node])
    assert rest == text <> "\n```````"
    tilde = put_in(node, ["attributes", "language"], "language`info")
    assert {:ok, "~~~~~language`info\n" <> rest} = CollaborativeProse.to_markdown([tilde])
    assert rest == text <> "\n~~~~~"
  end
end
