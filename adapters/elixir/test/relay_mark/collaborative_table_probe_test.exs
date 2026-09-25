defmodule RelayMark.CollaborativeTableProbeTest do
  use ExUnit.Case, async: true

  test "actual community table XML is rejected rather than losing cell spans in Markdown" do
    path =
      Path.expand(
        "../../../swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/table-experimental.json",
        __DIR__
      )

    fixture = path |> File.read!() |> Jason.decode!()

    for item <- fixture["cases"] do
      nodes = Enum.map(item["snapshot"]["children"], &codec_node/1)

      assert {:error, {:unsupported_collaboration_content, {:node, "table"}}} =
               RelayMark.CollaborativeProse.to_markdown(nodes)
    end
  end

  defp codec_node(%{"kind" => "text", "delta" => delta}), do: %{"delta" => delta}

  defp codec_node(node) do
    %{
      "tag" => node["name"],
      "attributes" => node["attributes"],
      "children" => Enum.map(node["children"], &codec_node/1)
    }
  end
end
