defmodule RelayMarkVideoValidatorTest do
  use ExUnit.Case, async: true

  @fixture Path.expand("../../../spec/relaymark/collaboration/fixtures/rich-video-v3-draft.json", __DIR__)

  test "validates the exact video AST from the TipTap/Yjs fixture" do
    ast = @fixture |> File.read!() |> Jason.decode!() |> Map.fetch!("expected_ast")
    assert :ok = RelayMark.validate_document(ast)

    malformed = put_in(ast, ["blocks", Access.at(1), "props", "videoId"], "../private")
    assert {:error, diagnostics} = RelayMark.validate_document(malformed)
    assert Enum.any?(diagnostics, &(&1["code"] == "relaymark.video_embed.id"))

    hidden = put_in(ast, ["blocks", Access.at(1), "content"], [%{"type" => "text", "text" => "hidden"}])
    assert {:error, diagnostics} = RelayMark.validate_document(hidden)
    assert Enum.any?(diagnostics, &(&1["code"] == "relaymark.video_embed.children"))
  end
end
