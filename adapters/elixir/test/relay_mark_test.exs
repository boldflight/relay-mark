defmodule RelayMarkTest do
  use ExUnit.Case, async: true

  test "decodes RelayMark document fixture" do
    assert {:ok, document} =
             "../../../spec/relaymark/examples/mentor-meeting.ast.json"
             |> fixture()
             |> RelayMark.decode_document()

    assert document.type == "relaymark.document"
    assert document.version == 1
    assert document.frontmatter["title"] == "Marcus interview prep"
    assert length(document.blocks) == 5

    source_bundle = Enum.at(document.blocks, 2)
    assert source_bundle.id == "src-1"
    assert source_bundle.type == "relay.source_bundle"
    assert source_bundle.props["scope"] == "private"
    assert hd(source_bundle.content).type == "relay.transcript_segment"

    action = Enum.at(document.blocks, 4)
    assert action.type == "relay.action_row"
    assert action.props["action"] == "relay.task.create"
    assert action.evidence_refs == ["src-1"]
    assert RelayMark.Block.plain_text(action) == "Send interview prep resources before Thursday."
  end

  test "decodes RelayMark manifest fixture" do
    assert {:ok, manifest} =
             "../../../spec/relaymark/examples/mentor-meeting.manifest.json"
             |> fixture()
             |> RelayMark.decode_manifest()

    assert manifest.type == "relaymark.manifest"
    assert [action] = manifest.actions
    assert action.block_id == "b5"
    assert action.action == "relay.task.create"
    assert action.args["title"] == "Send interview prep resources before Thursday."
    assert Enum.map(manifest.sources, & &1.kind) == ["source_bundle", "transcript_range"]
    assert manifest.diagnostics == []
  end

  defp fixture(relative_path) do
    __DIR__
    |> Path.join(relative_path)
    |> Path.expand()
    |> File.read!()
  end
end
