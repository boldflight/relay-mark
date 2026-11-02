defmodule RelayMark.EmptyDocumentTest do
  use ExUnit.Case, async: true

  # The empty document is valid everywhere: an empty fragment, an empty AST and an empty body
  # agree (spec/relaymark/editor/empty-document-v1.json, shared with the Rust engine and Swift).
  @fixture Path.expand("../../../spec/relaymark/editor/empty-document-v1.json", __DIR__)
  @external_resource @fixture
  @cases @fixture |> File.read!() |> Jason.decode!() |> Map.fetch!("cases")

  test "the fixture has the cases this adapter runs" do
    assert length(@cases) == 4
  end

  for %{"name" => name, "job" => job, "input" => input, "expected" => expected} <- @cases do
    test name do
      input = unquote(Macro.escape(input))
      expected = unquote(Macro.escape(expected))

      result =
        case unquote(job) do
          "to_snapshot" -> RelayMark.DocumentXML.from_document(input)
          "from_snapshot" -> RelayMark.DocumentXML.to_document(input)
          "normalize" -> RelayMark.DocumentXML.normalize_document(input)
          "project" -> RelayMark.project_document(input) |> project_shape()
        end

      assert {:ok, ^expected} = result
    end
  end

  defp project_shape({:ok, %{body: body, body_html: html}}),
    do: {:ok, %{"body" => body, "body_html" => html}}

  defp project_shape(other), do: other
end
