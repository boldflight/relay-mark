defmodule RelayMark.DocumentSourceTest do
  use ExUnit.Case, async: true

  @tag :canonical_directive_names
  test "authored video Markdown uses its registered directive and reparses without losing media identity" do
    source = ~s|@VideoEmbed(videoId: "530dd8cb-3f36-47e1-925d-7969cd81aa67") {

}|
    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "video-source-roundtrip")
    assert {:ok, exact} = RelayMark.serialize_document(ast)
    assert {:ok, ^ast} = RelayMark.parse_document(exact)
    assert {:ok, projected} = RelayMark.project_document_markdown(ast)
    assert projected == source <> "\n"
    assert {:ok, ^ast} = RelayMark.parse_document(projected, namespace: "video-source-roundtrip")
  end

  @tag :canonical_directive_names
  test "authored question Markdown uses its registered directive and reparses its rich label" do
    source = ~s|@FormQuestion(id: "care", type: "short_text") {
**Choose carefully 🌍**
}|
    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "question-source-roundtrip")
    assert {:ok, exact} = RelayMark.serialize_document(ast)
    assert {:ok, ^ast} = RelayMark.parse_document(exact)
    assert {:ok, projected} = RelayMark.project_document_markdown(ast)
    assert String.starts_with?(projected, "@FormQuestion(")

    assert {:ok, ^ast} =
             RelayMark.parse_document(projected, namespace: "question-source-roundtrip")
  end

  test "derived Markdown keeps structural numbers stable after collaborative JSON decoding" do
    source =
      "<!-- relay:question id=\"projection\" type=\"slot_picker\" -->\nChoose **carefully**\n<!-- /relay:question -->"

    assert {:ok, imported} = RelayMark.import_source(source, namespace: "projection-numbers")
    settings = %{"unknown" => %{"count" => 7, "fraction" => 0.25, "literal" => "0.0"}}
    decoded_settings = put_in(settings, ["unknown", "count"], 7.0)

    integer_ast =
      update_in(imported.document, ["blocks"], fn [question] ->
        [
          update_in(question, ["props"], fn props ->
            Map.merge(props, %{"points" => 0, "min" => 0, "max" => 0.5, "settings" => settings})
          end)
        ]
      end)

    decoded_ast =
      update_in(integer_ast, ["blocks"], fn [question] ->
        [
          update_in(question, ["props"], fn props ->
            Map.merge(props, %{"points" => 0.0, "min" => 0.0, "settings" => decoded_settings})
          end)
        ]
      end)

    assert {:ok, integer_markdown} = RelayMark.project_document_markdown(integer_ast)
    assert {:ok, decoded_markdown} = RelayMark.project_document_markdown(decoded_ast)
    assert decoded_markdown == integer_markdown
    assert decoded_markdown =~ "points: 0,"
    refute decoded_markdown =~ "points: 0.0"
    assert decoded_markdown =~ "min: 0,"
    assert decoded_markdown =~ "max: 0.5"

    assert decoded_markdown =~
             ~s|settings: {"unknown":{"count":7,"fraction":0.25,"literal":"0.0"}}|

    assert get_in(decoded_ast, ["blocks", Access.at(0), "props", "points"]) === 0.0
    assert get_in(decoded_ast, ["blocks", Access.at(0), "props", "settings"]) === decoded_settings
  end

  test "DataView keeps its eight authored fields across packaged source normalization" do
    source =
      ~s|@DataView(source: "pulse.streak", projection: "calendar", columns: ["day", "value"], filter: {basis: "care"}, sort: ["day"], group: "basis", limit: 10, title: "Work")|

    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "data-view-eight-fields")

    assert hd(ast["blocks"])["props"] == %{
             "source" => "pulse.streak",
             "projection" => "calendar",
             "columns" => ["day", "value"],
             "filter" => %{"basis" => "care"},
             "sort" => ["day"],
             "group" => "basis",
             "limit" => 10,
             "title" => "Work"
           }

    assert {:ok, exact} = RelayMark.serialize_document(ast)
    assert {:ok, ^ast} = RelayMark.parse_document(exact)
    assert {:ok, markdown} = RelayMark.project_document_markdown(ast)
    assert {:ok, ^ast} = RelayMark.parse_document(markdown, namespace: "data-view-eight-fields")

    assert {:error, _} =
             RelayMark.parse_document(
               String.replace(source, ~s|title: "Work"|, ~s|title: "Work", records: []|)
             )
  end

  test "source heading anchors roundtrip without consuming literal marker text" do
    source = "## Original {#h-stable}\n\n### **Renamed** {#h-second}\n\n## Duplicate {#h-stable}"
    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "heading-source")

    assert Enum.map(ast["blocks"], & &1["props"]["headingId"]) == [
             "h-stable",
             "h-second",
             "h-stable"
           ]

    assert {:ok, source} = RelayMark.project_document_markdown(ast)
    assert {:ok, ^ast} = RelayMark.parse_document(source, namespace: "heading-source")

    for source <- [
          "## Literal \\{#plain\\}",
          "## `Code {#plain}`",
          "## **Marked {#plain}**",
          "## 世界 {#unicode}"
        ] do
      assert {:ok, literal} = RelayMark.parse_document(source, namespace: "literal-heading")
      assert {:ok, projected} = RelayMark.project_document_markdown(literal)
      assert {:ok, ^literal} = RelayMark.parse_document(projected, namespace: "literal-heading")
    end
  end

  test "static nullable heading projects canonical destination and retains authored null" do
    fixture =
      Path.expand(
        "../../../spec/relaymark/collaboration/fixtures/canonical-heading-destinations.json",
        __DIR__
      )
      |> File.read!()
      |> Jason.decode!()

    assert {:ok, ast} =
             RelayMark.parse_document(fixture["source"], namespace: "static-null-heading")

    ast =
      put_in(
        ast,
        ["blocks", Access.at(fixture["explicit_heading_index"]), "props", "headingId"],
        fixture["explicit_heading_id"]
      )

    assert {:ok, html} = RelayMark.render_document(ast)

    assert Regex.scan(~r/<h[1-6] id="([^"]+)"/, html) |> Enum.map(&Enum.at(&1, 1)) ==
             fixture["heading_destinations"]

    refute html =~ ~s|id="chapter-private-label|
    assert html =~ "&quot;headingId&quot;:null"
    assert get_in(ast, ["blocks", Access.at(1), "props", "headingId"]) == nil
  end

  test "historical one-line DataView preserves exact props and code while malformed declarations refuse" do
    line =
      ~s|@DataView(source: "pulse.streak", projection: "calendar", filter: {basis: "work"}, limit: 30, title: "Retained Ω")|

    suffix = "\n\n```text\n" <> line <> "\n```\n\n    " <> line <> "\n"
    assert {:ok, ast} = RelayMark.parse_document(line <> suffix, namespace: "historic-data-view")
    assert Enum.map(ast["blocks"], & &1["type"]) == ["relay.data_view", "code", "code"]

    assert hd(ast["blocks"])["props"] == %{
             "source" => "pulse.streak",
             "projection" => "calendar",
             "filter" => %{"basis" => "work"},
             "limit" => 30,
             "title" => "Retained Ω"
           }

    for code <- tl(ast["blocks"]),
        do: assert(code["content"] == [%{"type" => "text", "text" => line <> "\n"}])

    assert {:ok, ^ast} =
             RelayMark.parse_document(line <> " {\n}" <> suffix, namespace: "historic-data-view")

    assert {:ok, snapshot} = RelayMark.DocumentXML.from_document(ast)
    assert {:ok, ^ast} = RelayMark.DocumentXML.to_document(snapshot)
    assert {:ok, exact} = RelayMark.serialize_document(ast)
    assert {:ok, ^ast} = RelayMark.parse_document(exact)

    for invalid <- [
          ~s|@DataView(source: "pulse.streak")|,
          ~s|@DataView(source: "https://example.test", projection: "calendar")|,
          ~s|@DataView(source: "pulse.streak", projection: "sql")|,
          ~s|@DataView(source: "pulse.streak", source: "pulse.work", projection: "calendar")|,
          ~s|@DataView(source: "pulse.streak", projection: "calendar", filter: {basis: {query: "sql"}})|,
          ~s|@DataView(source: "pulse.streak", projection: "calendar", limit: 0)|
        ],
        do: assert({:error, _} = RelayMark.parse_document(invalid))
  end

  test "malformed frozen historical child collections refuse without crashing the migration scan" do
    for document <- [
          %{"type" => "unsupported"},
          %{"type" => "relaymark.document", "blocks" => nil},
          %{"type" => "relaymark.document", "blocks" => %{}},
          %{
            "type" => "relaymark.document",
            "blocks" => [%{"type" => "paragraph", "id" => "historic", "content" => nil}]
          }
        ] do
      assert {:error, [%{"code" => "relaymark.import.invalid", "reason" => ":historical_shape"}]} =
               RelayMark.import_document(document, namespace: "malformed-frozen-publication")
    end
  end

  test "link title and safe properties persist through rich XML and safe rendering" do
    assert {:ok, ast} =
             RelayMark.parse_document(~s|[Label](https://example.com/path "Tooltip 🌍")|,
               namespace: "link-properties"
             )

    assert get_in(ast, ["blocks", Access.at(0), "content", Access.at(0), "props"]) == %{
             "title" => "Tooltip 🌍"
           }

    props = %{
      "target" => "_self",
      "rel" => "author nofollow",
      "class" => "paper-link cited",
      "title" => "Tooltip \"quoted\" 🌍"
    }

    ast = put_in(ast, ["blocks", Access.at(0), "content", Access.at(0), "props"], props)
    assert {:ok, xml} = RelayMark.DocumentXML.from_document(ast)
    assert {:ok, ^ast} = RelayMark.DocumentXML.to_document(xml)
    assert {:ok, source} = RelayMark.serialize_document(ast)
    assert {:ok, ^ast} = RelayMark.parse_document(source)

    for properties <- [
          %{"target" => nil, "rel" => nil, "title" => ""},
          %{"target" => "123 reading 🌍", "rel" => "", "class" => "citation", "title" => "Line\n🌍"}
        ] do
      declaration =
        put_in(ast, ["blocks", Access.at(0), "content", Access.at(0), "props"], properties)

      assert {:ok, snapshot} = RelayMark.DocumentXML.from_document(declaration)
      assert {:ok, ^declaration} = RelayMark.DocumentXML.to_document(snapshot)
    end

    assert {:ok, html} = RelayMark.render_document(ast)

    assert html =~
             ~s|target="_self" rel="author nofollow" class="paper-link cited" title="Tooltip &quot;quoted&quot; 🌍"|

    for invalid <- [
          %{"href" => "javascript:alert(1)"},
          %{"target" => "_unknown"},
          %{"target" => "_blank\n"},
          %{"rel" => <<0>>},
          %{"class" => <<0>>},
          %{"title" => 42},
          %{"onclick" => "alert(1)"}
        ] do
      attrs = Map.merge(Map.put(props, "href", "https://example.com/path"), invalid)
      assert {:error, _} = RelayMark.DocumentXML.validate_text_attributes(%{"link" => attrs})
    end
  end

  test "single and multi select preserve rich choices, IDs and authored settings" do
    for {type, first, second} <- [{"single_select", "(x)", "( )"}, {"multi_select", "[x]", "[ ]"}] do
      source = """
      <!-- relay:question id="choose" type="#{type}" settings='{"randomize":true}' options='[{"id":"first","settings":{"score":3}},{"id":"second","settings":{"hint":"kept"}}]' -->
      **Choose 🌍**
      - #{first} **Bold choice**
      - #{second} Code `Ω`
      <!-- /relay:question -->
      """

      assert {:ok, ast} = RelayMark.parse_document(source, namespace: "choice-source")
      [question] = ast["blocks"]
      assert question["props"]["type"] == type
      assert question["props"]["settings"] == %{"randomize" => true}
      [label, first, second] = question["content"]

      assert label["content"] == [
               %{"type" => "strong", "content" => [%{"type" => "text", "text" => "Choose 🌍"}]}
             ]

      assert first["props"]["id"] == "first"
      assert second["props"]["id"] == "second"
      assert first["props"]["correct"] == true
      assert second["props"]["correct"] == false
      assert first["props"]["settings"] == %{"score" => 3}
      assert second["props"]["settings"] == %{"hint" => "kept"}

      assert first["content"] == [
               %{"type" => "strong", "content" => [%{"type" => "text", "text" => "Bold choice"}]}
             ]

      assert List.last(second["content"])["type"] == "code_span"
      assert {:ok, exact} = RelayMark.serialize_document(ast)
      assert {:ok, ^ast} = RelayMark.parse_document(exact)
    end
  end

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

  test "full authored reference titles survive source decoding and strict XML roundtrip" do
    label = " [A]\n\"B\"\\ "

    source =
      ~S([[Person: 11111111-1111-4111-8111-111111111111 | "\u0020\u005b\u0041\u005d\u000a\u0022\u0042\u0022\u005c\u0020"]])

    assert {:ok, ^source} =
             RelayMark.InlineAtoms.reference_source(
               "Person",
               "11111111-1111-4111-8111-111111111111",
               label
             )

    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "reference-title")
    assert hd(hd(ast["blocks"])["content"])["label"] == label
    assert {:ok, xml} = RelayMark.DocumentXML.from_document(ast)
    assert {:ok, ^ast} = RelayMark.DocumentXML.to_document(xml)
  end

  test "onboarding static image paths survive canonical source and XML" do
    for src <- ["/images/onboarding/connected-note.png", "/images/onboarding/connected-work.png"] do
      assert {:ok, ast} =
               RelayMark.parse_document("![Connected](#{src})", namespace: "onboarding-image")

      assert hd(ast["blocks"])["props"]["src"] == src
      assert {:ok, snapshot} = RelayMark.DocumentXML.from_document(ast)
      assert {:ok, ^ast} = RelayMark.DocumentXML.to_document(snapshot)
    end
  end

  test "historical onboarding compact refs and linked tasks retain identities and code literals" do
    source =
      "Contact [[Person:11111111-1111-4111-8111-111111111111|Alex Morgan — Sample]].\n\n[ ] **Review** [[Task:22222222-2222-4222-8222-222222222222]]\n- [x] [[Task:33333333-3333-4333-8333-333333333333]]\n- [ ] Local <!--relay-task-draft:44444444-4444-4444-8444-444444444444-->\n\n`[[Task:44444444-4444-4444-8444-444444444444]]`\n\n```text\n[[Task:44444444-4444-4444-8444-444444444444]]\n```"

    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "historical-tasks")

    fixture =
      Path.expand(
        "../../../spec/relaymark/collaboration/fixtures/canonical-historical-source.json",
        __DIR__
      )
      |> File.read!()
      |> Jason.decode!()

    assert source == fixture["source"]
    assert ast == fixture["expected_ast"]
    [paragraph, task_list, code_paragraph, code] = ast["blocks"]

    assert Enum.at(paragraph["content"], 1)["props"]["source"] ==
             "[[Person: 11111111-1111-4111-8111-111111111111 | Alex Morgan — Sample]]"

    assert Enum.map(task_list["content"], & &1["props"]) == [
             %{"checked" => false, "entityId" => "22222222-2222-4222-8222-222222222222"},
             %{"checked" => true, "entityId" => "33333333-3333-4333-8333-333333333333"},
             %{"checked" => false, "entityId" => nil}
           ]

    assert hd(hd(task_list["content"])["content"])["content"] == [
             %{"type" => "strong", "content" => [%{"type" => "text", "text" => "Review"}]}
           ]

    assert hd(Enum.at(task_list["content"], 1)["content"])["content"] == []

    assert hd(Enum.at(task_list["content"], 2)["content"])["content"] == [
             %{"type" => "text", "text" => "Local"}
           ]

    assert hd(hd(code_paragraph["content"])["content"])["text"] ==
             "[[Task:44444444-4444-4444-8444-444444444444]]"

    assert hd(code["content"])["text"] == "[[Task:44444444-4444-4444-8444-444444444444]]\n"
    assert {:ok, exact} = RelayMark.serialize_document(ast)
    refute exact =~ "relay-task-draft"
    refute exact =~ "draftId"
  end

  test "historical raw HTML and malformed wiki source retain literal text without executable output" do
    source =
      "Before <script>alert(1)</script> [[Person:bad|Title]] after.\n\n<div onclick=\"evil()\">Raw [[Task:bad]]</div>\n"

    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "literal-html")

    assert Enum.map_join(hd(ast["blocks"])["content"], & &1["text"]) ==
             "Before <script>alert(1)</script> [[Person:bad|Title]] after."

    assert hd(Enum.at(ast["blocks"], 1)["content"])["text"] ==
             "<div onclick=\"evil()\">Raw [[Task:bad]]</div>\n"

    assert {:ok, html} = RelayMark.render_document(ast)
    refute html =~ "<script"
    refute html =~ "<div onclick"
    assert html =~ "&lt;script&gt;alert"
  end

  test "callout HTML-looking title retains exact literal value instead of an empty title" do
    source =
      ~s|@Callout(title: "<img src=x onerror=alert(1)>", tone: "warning", emphasis: "strong") {\nBody **words**\n}|

    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "callout-literal-title")

    assert hd(hd(hd(ast["blocks"])["content"])["content"])["text"] ==
             "<img src=x onerror=alert(1)>"

    assert {:ok, html} = RelayMark.render_document(ast)
    assert html =~ ~s|<div data-callout-title="true">&lt;img src=x onerror=alert(1)&gt;</div>|
  end

  test "historical block reference bare IDs and unindented bodies normalize to one strict atom" do
    id = "11111111-1111-4111-8111-111111111111"

    for input <- [id, "entity:" <> id] do
      source = ~s|@EntityRef(id: "#{input}", projection: "card") {\nAuthored fallback\n}|
      assert {:ok, ast} = RelayMark.parse_document(source, namespace: "old-block-ref")

      assert hd(ast["blocks"])["props"] == %{
               "id" => "entity:" <> id,
               "label" => "Authored fallback",
               "projection" => "card",
               "source" =>
                 ~s|@EntityRef(id: "entity:#{id}", label: "Authored fallback", projection: "card") {\n  Authored fallback\n}|
             }

      assert {:ok, xml} = RelayMark.DocumentXML.from_document(ast)
      assert {:ok, ^ast} = RelayMark.DocumentXML.to_document(xml)
    end
  end

  test "historical standalone video and GIF declarations become durable media while code stays literal" do
    source =
      "::video[/v/11111111-1111-4111-8111-111111111111]\n\nhttps://example.com/a.gif\n\n[https://example.com/b.gif](https://example.com/b.gif)\n\n<https://example.com/c.gif>\n\n`::video[/v/11111111-1111-4111-8111-111111111111]`"

    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "old-media")

    assert Enum.map(ast["blocks"], & &1["type"]) == [
             "relay.video_embed",
             "image",
             "image",
             "image",
             "paragraph"
           ]

    assert hd(ast["blocks"])["props"]["videoId"] == "11111111-1111-4111-8111-111111111111"

    assert ast["blocks"] |> Enum.slice(1, 3) |> Enum.map(& &1["props"]["src"]) == [
             "https://example.com/a.gif",
             "https://example.com/b.gif",
             "https://example.com/c.gif"
           ]

    assert hd(List.last(ast["blocks"])["content"])["type"] == "code_span"
  end

  test "finite reference normalization rejects duplicate identity and unsupported attributes" do
    id = "11111111-1111-4111-8111-111111111111"

    for attrs <- [
          ~s|id: "#{id}", id: "#{id}"|,
          ~s|id: "#{id}", surprise: "value"|,
          ~s|id: "#{id}", projection: "popover"|
        ] do
      assert {:error, _} =
               RelayMark.parse_document("@EntityRef(" <> attrs <> ") {\nBody\n}",
                 namespace: "ambiguous-reference"
               )
    end
  end

  test "indented authored directive examples remain maintained code blocks after a real reference" do
    id = "11111111-1111-4111-8111-111111111111"
    example = "22222222-2222-4222-8222-222222222222"

    source =
      ~s|@EntityRef(id: "#{id}", projection: "chip") {\nReal reference\n}\n\n```relaymark\n@EntityRef(id: "#{example}") {\nExample\n}\n```\n\n    @EntityRef(id: "#{example}") {\n    Indented example\n    }\n\n`[[Person: #{example} \| Inline example]]`|

    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "reference-code-context")

    assert Enum.map(ast["blocks"], & &1["type"]) == [
             "relay.entity_reference",
             "code",
             "code",
             "paragraph"
           ]

    assert hd(ast["blocks"])["props"]["id"] == "entity:" <> id
    assert hd(Enum.at(ast["blocks"], 2)["content"])["text"] =~ "Indented example"
  end

  test "unsafe historical image and non-navigation links remain inert declaration text" do
    source =
      "![Image](relay:entity/11111111-1111-4111-8111-111111111111)\n\n[Query](relay:entity/11111111-1111-4111-8111-111111111111?view=paper)\n[Wrong](relay:entityx/11111111-1111-4111-8111-111111111111)"

    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "inert-declarations")
    assert hd(ast["blocks"])["type"] == "paragraph"

    assert hd(hd(ast["blocks"])["content"])["text"] ==
             "![Image](relay:entity/11111111-1111-4111-8111-111111111111)"

    assert {:ok, html} = RelayMark.render_document(ast)
    refute html =~ "<img"
    refute html =~ "<a"
    assert html =~ "[Query]"
  end

  test "linked task first-line identity survives lazy continuation with the same context reference" do
    id = "11111111-1111-4111-8111-111111111111"

    assert {:ok, ast} =
             RelayMark.parse_document(
               "- [ ] Keep deleted identity [[Task: #{id}]]\nSee [[Task: #{id} | Deleted task context]] for the decision history.\n",
               namespace: "linked-continuation"
             )

    item = hd(hd(ast["blocks"])["content"])
    assert item["props"]["entityId"] == id
    refs = hd(item["content"])["content"] |> Enum.filter(&(&1["type"] == "relay.entity_ref"))
    assert length(refs) == 1
    assert hd(refs)["label"] == "Deleted task context"
    assert hd(hd(item["content"])["content"])["text"] == "Keep deleted identity\nSee "
    assert {:ok, xml} = RelayMark.DocumentXML.from_document(ast)
    assert {:ok, ^ast} = RelayMark.DocumentXML.to_document(xml)
  end

  test "finite XML migration installs only stable identities without rebuilding rich text" do
    source =
      "@FormQuestion(id: \"q\", type: \"multiple_choice\") {\n**Choose 🌍**\n@FormOption(id: \"paris\", correct: false) {\nParis\n}\n}"

    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "existing")

    assert {:ok, original} =
             RelayMark.DocumentXML.from_document(Map.put(ast, "meta", %{"original" => true}))

    [question] = original["children"]

    question =
      question
      |> update_in(["attributes"], &Map.delete(&1, "relaymarkId"))
      |> update_in(["children"], fn nodes ->
        Enum.map(
          nodes,
          &update_in(&1, ["attributes"], fn attrs -> Map.delete(attrs, "relaymarkId") end)
        )
      end)

    original = Map.put(original, "children", [question])

    assert {:ok, first} =
             RelayMark.DocumentXML.import_snapshot(original, namespace: "paper-incarnation")

    assert {:ok, ^first} =
             RelayMark.DocumentXML.import_snapshot(original, namespace: "paper-incarnation")

    assert first["requires_reconstruction"] == false
    assert length(first["normalizations"]) == 3

    assert get_in(first, ["snapshot", "children", Access.at(0), "attributes", "relaymarkId"]) ==
             "b4295cba87f50493182317a0ad04584a4"

    assert get_in(first, [
             "snapshot",
             "children",
             Access.at(0),
             "children",
             Access.at(1),
             "children"
           ]) ==
             get_in(original, ["children", Access.at(0), "children", Access.at(1), "children"])

    assert first["snapshot"]["metadata"] == original["metadata"]

    assert {:ok, unchanged} =
             RelayMark.DocumentXML.import_snapshot(first["snapshot"],
               namespace: "paper-incarnation"
             )

    assert unchanged["normalizations"] == []
    bad = put_in(original, ["children", Access.at(0), "attributes", "options"], ["lossy"])

    assert {:error, _} =
             RelayMark.DocumentXML.import_snapshot(bad, namespace: "paper-incarnation")
  end

  test "finite exact source import retains rich content while resetting historical identities" do
    original = %{
      "type" => "relaymark.document",
      "version" => 1,
      "blocks" => [
        %{
          "id" => "old-note",
          "type" => "paragraph",
          "content" => [
            %{"type" => "strong", "content" => [%{"type" => "text", "text" => "Résumé 🌍"}]}
          ]
        }
      ]
    }

    source = "```relaymark-ast\n" <> Jason.encode!(original) <> "\n```\n"
    assert {:error, _} = RelayMark.parse_document(source)
    assert {:ok, first} = RelayMark.import_source(source, namespace: "historical-source")
    assert RelayMark.import_source(source, namespace: "historical-source") == {:ok, first}
    assert {:ok, direct} = RelayMark.import_document(original, namespace: "historical-source")
    assert first == direct
    assert hd(first.document["blocks"])["id"] == "b3caafb0d7c034362851808ae213c59be"
    refute Map.has_key?(first.document, "version")
  end

  test "canonical typing attributes share full mark and safe link validation" do
    assert :ok =
             RelayMark.DocumentXML.validate_text_attributes(%{
               "underline" => %{},
               "highlight" => %{},
               "superscript" => %{}
             })

    link = %{
      "href" => "https://example.com/evidence",
      "target" => "_blank",
      "rel" => "noopener noreferrer nofollow",
      "class" => nil,
      "title" => nil
    }

    assert :ok = RelayMark.DocumentXML.validate_text_attributes(%{"link" => link, "bold" => %{}})

    for attrs <- [
          %{"code" => %{}, "bold" => %{}},
          %{"link" => Map.put(link, "href", "javascript:alert(1)")},
          %{"underline" => %{"enabled" => true}},
          %{"unknown" => %{}}
        ] do
      assert {:error, _} = RelayMark.DocumentXML.validate_text_attributes(attrs)
    end
  end

  test "finite inline media boundary repair preserves rich text and exact independent shared identities" do
    f =
      Jason.decode!(
        File.read!(
          Path.expand(
            "../../../spec/relaymark/collaboration/fixtures/canonical-inline-media.json",
            __DIR__
          )
        )
      )

    assert {:ok, ast} = RelayMark.parse_document(f["source"], namespace: f["namespace"])
    assert ast == f["expected_ast"]
    assert {:ok, xml} = RelayMark.DocumentXML.from_document(ast)
    assert {:ok, ^ast} = RelayMark.DocumentXML.to_document(xml)
  end
  test "authored FileRef retains its physical reference and rich children through body projection" do
    id = "11111111-1111-4111-8111-111111111111"
    source = ~s|@FileRef(id: "#{id}", uri: "/m/#{id}", label: "Care Ω.pdf", scope: "private") {\n**Retained** file context\n}|
    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "authored-file-projection")
    [file] = ast["blocks"]
    assert file["type"] == "relay.file_ref"
    assert file["props"] == %{"id" => id, "uri" => "/m/#{id}", "label" => "Care Ω.pdf", "scope" => "private"}
    assert {:ok, exact} = RelayMark.serialize_document(ast)
    assert {:ok, ^ast} = RelayMark.parse_document(exact)
    assert {:ok, markdown} = RelayMark.project_document_markdown(ast)
    assert markdown =~ "@FileRef("
    assert markdown =~ ~s|id: "#{id}"|
    assert markdown =~ ~s|uri: "/m/#{id}"|
    assert markdown =~ ~s|label: "Care Ω.pdf"|
    assert markdown =~ "**Retained** file context"
    assert {:ok, ^ast} = RelayMark.parse_document(markdown, namespace: "authored-file-projection")
    assert {:ok, projection} = RelayMark.DocumentSource.project_with_render(ast, fn _ -> "resolved-file-render" end)
    assert projection.body == markdown
  end

  test "SourceBundle wrapped FileRef projects through the canonical directive registry without losing its original" do
    id = "11111111-1111-4111-8111-111111111111"
    source = ~s|@SourceBundle(id: "care-sources", title: "Care Ω", revision: 0, scope: "private") {\n@FileRef(id: "#{id}", uri: "/m/#{id}", label: "Care Ω.pdf", scope: "private") {\n**Retained** file context\n}\n}|
    assert {:ok, ast} = RelayMark.parse_document(source, namespace: "source-bundle-file-wrap")
    [bundle] = ast["blocks"]
    [file] = bundle["content"]
    assert bundle["type"] == "relay.source_bundle"
    assert bundle["props"] == %{"id" => "care-sources", "title" => "Care Ω", "revision" => 0, "scope" => "private"}
    assert file["type"] == "relay.file_ref"
    assert file["props"] == %{"id" => id, "uri" => "/m/#{id}", "label" => "Care Ω.pdf", "scope" => "private"}
    assert {:ok, exact} = RelayMark.serialize_document(ast)
    assert {:ok, ^ast} = RelayMark.parse_document(exact)
    assert {:ok, markdown} = RelayMark.project_document_markdown(ast)
    assert markdown =~ "@SourceBundle("
    assert markdown =~ "@FileRef("
    assert markdown =~ "**Retained** file context"
    assert {:ok, ^ast} = RelayMark.parse_document(markdown, namespace: "source-bundle-file-wrap")
    assert {:ok, projection} = RelayMark.DocumentSource.project_with_render(ast, fn _ -> "resolved-bundle-render" end)
    assert projection.body == markdown
  end

  test "maintained evidence claim comparison corpus remains readable through the same directive registry" do
    ast = Path.expand("../../../spec/relaymark/collaboration/fixtures/canonical-directives.json", __DIR__)
          |> File.read!() |> Jason.decode!()
    assert {:ok, exact} = RelayMark.serialize_document(ast)
    assert {:ok, normalized} = RelayMark.parse_document(exact)
    assert {:ok, projection} = RelayMark.DocumentSource.project_with_render(normalized, fn _ -> "resolved-evidence-render" end)
    for name <- ["EvidenceRef", "Claim", "Comparison"], do: assert(projection.body =~ "@#{name}(")
    assert {:ok, ^normalized} = RelayMark.parse_document(exact)
    assert {:error, _} = RelayMark.project_document_markdown(%{"type" => "relaymark.document", "blocks" => [%{"id" => "b00000000000040008000000000000001", "type" => "relay.unknown", "props" => %{}, "content" => []}]})
  end

end
