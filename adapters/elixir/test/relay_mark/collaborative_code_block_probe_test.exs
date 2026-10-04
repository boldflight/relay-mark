defmodule RelayMark.CollaborativeCodeBlockProbeTest do
  use ExUnit.Case, async: true

  @fixture Path.expand(
             "../../../swift/Tests/RelayMarkNativeCollaborationTests/Fixtures/code-block-v1.json",
             __DIR__
           )

  test "actual browser multiline code state uses a lossless dynamic fence" do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    nodes = Enum.map(fixture["after"]["children"], &tree/1)
    expected = "````swift\n" <> fixture["initial"] <> fixture["inserted"] <> "\n````"
    assert {:ok, ^expected} = RelayMark.CollaborativeProse.to_markdown(nodes)
  end

  defp tree(%{"kind" => "text", "delta" => delta}), do: %{"delta" => delta}

  defp tree(node),
    do: %{
      "tag" => node["name"],
      "attributes" => node["attributes"],
      "children" => Enum.map(node["children"], &tree/1)
    }
end
