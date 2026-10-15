defmodule RelayMark.SourceCompatibilityTest do
  use ExUnit.Case, async: true

  test "CommonMark list items preserve nonparagraph first blocks behind an empty paragraph" do
    for {source, expected} <- [
          {"- ", nil},
          {"- # Heading\n\n  Body", "heading"},
          {"- > Quoted", "quote"},
          {"- - Nested", "list"},
          {"- ```\n  code\n  ```", "code"}
        ] do
      assert {:ok, result} = RelayMark.import_source(source, namespace: "historical-list")
      [item] = hd(result.document["blocks"])["content"]
      assert [paragraph | rest] = item["content"]
      assert paragraph["type"] == "paragraph"
      assert paragraph["content"] == []
      if expected, do: assert(hd(rest)["type"] == expected), else: assert(rest == [])
      assert {:ok, repeated} = RelayMark.import_source(source, namespace: "historical-list")
      assert repeated.document == result.document
      assert :ok = RelayMark.validate_document(result.document)
    end
  end

  test "marked ordinary wiki text retains its literal source and emphasis" do
    assert {:ok, result} =
             RelayMark.import_source("**[[Retained label]]**", namespace: "marked-wiki")

    assert hd(result.document["blocks"])["content"] == [
             %{
               "type" => "strong",
               "content" => [%{"type" => "text", "text" => "[[Retained label]]"}]
             }
           ]
  end

  test "a hard break inside strong text preserves the break and both marked runs" do
    assert {:ok, result} =
             RelayMark.import_source("**Before  \nAfter**", namespace: "marked-break")

    assert hd(result.document["blocks"])["content"] == [
             %{"type" => "strong", "content" => [%{"type" => "text", "text" => "Before"}]},
             %{"type" => "hard_break"},
             %{"type" => "strong", "content" => [%{"type" => "text", "text" => "After"}]}
           ]

    assert :ok = RelayMark.validate_document(result.document)
  end

  test "registered directives without attributes use their declared defaults" do
    assert {:ok, result} =
             RelayMark.import_source("@Callout {\nRetained body.\n}\n",
               namespace: "directive-defaults"
             )

    assert hd(result.document["blocks"])["type"] == "relay.callout"
    assert hd(result.document["blocks"])["props"]["tone"] == "neutral"
  end

  test "a relocated source module imports registered directives from installed application priv" do
    source = Path.expand("../lib/relay_mark/document_source.ex", __DIR__)
    directive = "@Callout(tone: \"info\") {\nRetained body.\n}\n"

    expression = """
    Code.compiler_options(ignore_module_conflict: true)
    Code.compile_string(File.read!(#{inspect(source)}), "/absent-relaymark-source/lib/relay_mark/document_source.ex")
    case RelayMark.import_source(#{inspect(directive)}, namespace: "relocated-source") do
      {:ok, %{document: %{"blocks" => [%{"type" => "relay.callout"}]}}} -> IO.puts("RELOCATED_DIRECTIVE_OK")
      _ -> System.halt(3)
    end
    """

    paths = :code.get_path() |> Enum.flat_map(&["-pa", List.to_string(&1)])

    {output, exit_code} =
      System.cmd("elixir", paths ++ ["-e", expression], stderr_to_stdout: true)

    assert exit_code == 0, output
    assert output =~ "RELOCATED_DIRECTIVE_OK"
  end

  test "source compatibility has one exact cross-runtime document and identity mapping" do
    fixture =
      Path.expand(
        "../../../spec/relaymark/collaboration/fixtures/canonical-source-compatibility.json",
        __DIR__
      )
      |> File.read!()
      |> Jason.decode!()

    assert {:ok, result} =
             RelayMark.import_source(fixture["source"], namespace: fixture["namespace"])

    assert result.document == fixture["expected_ast"]
  end

  test "marks around a canonical reference preserve its identity and neighboring text marks" do
    source = "**Before [[Note: 530dd8cb-3f36-47e1-925d-7969cd81aa67 | Kept note]] after**"
    assert {:ok, result} = RelayMark.import_source(source, namespace: "marked-reference")
    assert [before, reference, after_text] = hd(result.document["blocks"])["content"]

    assert before == %{
             "type" => "strong",
             "content" => [%{"type" => "text", "text" => "Before "}]
           }

    assert after_text == %{
             "type" => "strong",
             "content" => [%{"type" => "text", "text" => " after"}]
           }

    assert reference["type"] == "relay.entity_ref"
    assert reference["id"] == "530dd8cb-3f36-47e1-925d-7969cd81aa67"
    assert reference["label"] == "Kept note"
    assert reference["props"]["entityType"] == "Note"

    assert reference["props"]["source"] ==
             "[[Note: 530dd8cb-3f36-47e1-925d-7969cd81aa67 | Kept note]]"

    refute Map.has_key?(reference, "marks")
    assert :ok = RelayMark.validate_document(result.document)
  end
end
