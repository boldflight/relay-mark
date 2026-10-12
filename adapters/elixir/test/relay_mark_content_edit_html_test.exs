defmodule RelayMark.ContentEditHTMLTest do
  use ExUnit.Case, async: true

  test "shipped bounded QuickJS imports frozen HTML with real entity decoding and exact finite identity" do
    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)

    input = %{
      "html" =>
        "<h2>Historical caf&eacute; 世界</h2><p>Keep <strong>published meaning</strong> and <a href=\"https://example.test/original\">original source</a>.</p>",
      "namespace" => "retained-public-html"
    }

    assert {:ok, result} = RelayMark.ContentEdit.import_document_html(runtime, input)
    assert [heading, paragraph] = result["document"]["blocks"]
    assert heading["type"] == "heading"
    assert heading["props"]["level"] == 2
    assert heading["content"] == [%{"type" => "text", "text" => "Historical café 世界"}]

    assert Enum.at(paragraph["content"], 1) == %{
             "type" => "strong",
             "content" => [%{"type" => "text", "text" => "published meaning"}]
           }

    assert Enum.at(paragraph["content"], 3)["href"] == "https://example.test/original"
    assert length(result["identity_mapping"]["added"]) == 2
    assert Enum.any?(result["normalizations"], &(&1["operation"] == "import_retained_html"))
    assert {:ok, ^result} = RelayMark.ContentEdit.import_document_html(runtime, input)
  end

  test "same packaged runtime refuses unknown frozen source and enumerates absent private form fields" do
    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.import_document_html(runtime, %{
               "html" =>
                 "<p>Retained <iframe src=\"https://example.test/original\"></iframe> source</p>",
               "namespace" => "retained-unsupported"
             })

    assert {:ok, result} =
             RelayMark.ContentEdit.import_document_html(runtime, %{
               "html" =>
                 "<fieldset data-relay-question=\"q\" data-question-type=\"multiple_choice\" data-required=\"true\"><legend>Choose</legend><div data-relay-option=\"a\">Original option</div></fieldset>",
               "namespace" => "retained-visible-form"
             })

    assert [question] = result["document"]["blocks"]
    assert question["props"]["id"] == "q"
    assert question["props"]["required"]
    assert question["props"]["points"] == nil
    assert question["props"]["settings"] == %{}

    assert Enum.map(
             Enum.filter(
               result["normalizations"],
               &(&1["operation"] == "historical_html_absent_fields")
             ),
             & &1["attributes"]
           ) ==
             [["points", "min", "max", "settings"], ["correct", "points", "settings"]]
  end

  test "packaged import preserves a substantial Unicode original and refuses the actual byte bound without fallback" do
    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)
    original = String.duplicate("é", 100_000)
    input = %{"html" => "<p>" <> original <> "</p>", "namespace" => "retained-large-unicode"}
    assert {:ok, result} = RelayMark.ContentEdit.import_document_html(runtime, input)
    assert [paragraph] = result["document"]["blocks"]
    assert paragraph["content"] == [%{"type" => "text", "text" => original}]

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.import_document_html(runtime, %{
               "html" => String.duplicate("é", 2_097_153),
               "namespace" => "retained-byte-refusal"
             })

    assert {:ok, ^result} = RelayMark.ContentEdit.import_document_html(runtime, input)
  end

  test "packaged nil and empty retained HTML normalize the canonical empty paragraph with exact retry" do
    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)

    for html <- [nil, ""] do
      input = %{"html" => html, "namespace" => "retained-empty-#{inspect(html)}"}
      assert {:ok, result} = RelayMark.ContentEdit.import_document_html(runtime, input)
      assert [paragraph] = result["document"]["blocks"]
      assert paragraph["type"] == "paragraph"
      assert paragraph["content"] == []
      assert length(result["identity_mapping"]["added"]) == 1

      assert Enum.any?(
               result["normalizations"],
               &(&1["operation"] == "empty_retained_html" and &1["source_value"] == html)
             )

      assert {:ok, ^result} = RelayMark.ContentEdit.import_document_html(runtime, input)
    end
  end
end
