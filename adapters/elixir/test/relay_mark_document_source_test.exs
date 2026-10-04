defmodule RelayMark.DocumentSourceTest do
  use ExUnit.Case, async: true

  test "server CommonMark maps independent shared identities and marks" do
    path =
      Path.expand("../../../spec/relaymark/collaboration/fixtures/canonical-source.json", __DIR__)

    f = path |> File.read!() |> Jason.decode!()

    assert RelayMark.parse_document(f["source"], namespace: f["namespace"]) ==
             {:ok, f["expected_ast"]}
  end

  test "CommonMark rich import retains meaning, stable retry identities and exact source" do
    source =
      "# Title\n\n> **A** and [B](https://example.com)\n\n- [x] Task\n- [ ] Next\n\n| Name | Value |\n| --- | ---: |\n| A | B |\n\n@Callout(tone: \"info\", emphasis: \"soft\", title: \"Read\") {\n![Diagram](/m/asset)\n}\n"

    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "import-one")
    assert {:ok, ^ast} = RelayMark.parse_document(source, namespace: "import-one")

    assert Enum.map(ast["blocks"], & &1["type"]) == [
             "heading",
             "quote",
             "task_list",
             "table",
             "relay.callout"
           ]

    quote = Enum.at(ast["blocks"], 1)
    assert hd(hd(quote["content"])["content"])["type"] == "strong"
    assert {:ok, exact} = RelayMark.serialize_document(ast)
    assert String.starts_with?(exact, "```relaymark-ast\n")
    assert {:ok, ^ast} = RelayMark.parse_document(exact)
    assert {:ok, markdown} = RelayMark.project_document_markdown(ast)
    assert markdown =~ "**A**"
    assert markdown =~ "| Name | Value |"
    refute markdown =~ "relaymark-ast"
  end
end
