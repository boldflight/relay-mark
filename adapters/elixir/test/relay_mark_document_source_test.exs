defmodule RelayMark.DocumentSourceTest do
  use ExUnit.Case, async: true

  test "historical published questions preserve slug choices, rich labels, scoring and empty fields" do
    source =
      "<!-- relay:question id=\"q1\" type=\"multiple_choice\" required=\"true\" points=\"5\" conditional=\"show-q0\" -->\n**Capital?**\n- (x) Paris\n- ( ) London\n<!-- /relay:question -->\n\n<!-- relay:question id=\"q2\" type=\"short_text\" -->\n<!-- /relay:question -->\n"

    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "historic-paper")
    [q1, q2] = ast["blocks"]
    assert q1["type"] == "relay.form_question"

    assert q1["props"] == %{
             "id" => "q1",
             "type" => "multiple_choice",
             "required" => true,
             "points" => 5,
             "min" => nil,
             "max" => nil,
             "settings" => %{"conditional" => "show-q0"}
           }

    [label, paris, london] = q1["content"]

    assert label["content"] == [
             %{"type" => "strong", "content" => [%{"type" => "text", "text" => "Capital?"}]}
           ]

    assert paris["props"]["id"] == "paris"
    assert paris["props"]["correct"] == true
    assert london["props"]["id"] == "london"
    assert london["props"]["correct"] == false
    assert q2["props"]["id"] == "q2"
    assert hd(q2["content"])["content"] == []
  end

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

  test "finite migration wraps historic directive text and retains a stable identity mapping" do
    canonical =
      Path.expand(
        "../../../spec/relaymark/collaboration/fixtures/canonical-directives.json",
        __DIR__
      )
      |> File.read!()
      |> Jason.decode!()

    original =
      canonical
      |> Map.put("version", 1)
      |> update_in(["blocks", Access.at(0), "content"], &hd(&1)["content"])

    assert {:ok, result} = RelayMark.import_document(original, namespace: "historic-corpus")
    assert result == elem(RelayMark.import_document(original, namespace: "historic-corpus"), 1)
    assert hd(result.document["blocks"])["id"] == hd(original["blocks"])["id"]

    assert hd(hd(result.document["blocks"])["content"])["content"] ==
             hd(original["blocks"])["content"]

    assert result.identity_mapping["added"] == [
             %{
               "id" => "bb756b5f57e434fa48ec0d909a25264c1",
               "parent" => hd(original["blocks"])["id"],
               "role" => "inline_body",
               "index" => 0
             }
           ]

    assert {:ok, %{document: doc}} =
             RelayMark.import_document(result.document, namespace: "historic-corpus")

    assert doc == result.document
  end
end
