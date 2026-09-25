defmodule RelayMark.CollaborativeQuoteProbeTest do
  use ExUnit.Case, async: true
  @fixture Path.expand("../../../swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/quote-v1.json", __DIR__)
  test "actual browser quote preserves Unicode and bold source" do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    nodes = Enum.map(fixture["after"]["children"], &tree/1)
    assert {:ok, "> **QuoΩ ted 🌍 text**"} = RelayMark.CollaborativeProse.to_markdown(nodes)
  end
  defp tree(%{"kind" => "text", "delta" => delta}), do: %{"delta" => delta}
  defp tree(node), do: %{"tag" => node["name"], "attributes" => node["attributes"], "children" => Enum.map(node["children"], &tree/1)}
end
