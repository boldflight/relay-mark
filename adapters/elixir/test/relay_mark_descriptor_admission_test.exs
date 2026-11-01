defmodule RelayMark.DescriptorAdmissionTest do
  use ExUnit.Case, async: true

  @fixture Path.expand("../../../spec/relaymark/editor/descriptor-admission-v1.json", __DIR__)

  for item <- @fixture |> File.read!() |> Jason.decode!() |> Map.fetch!("cases") do
    @item item
    test "descriptor admission: #{item["name"]}" do
      item = @item

      case {RelayMark.Contract.admit(item["input"]), item} do
        {{:ok, actual}, %{"expected" => expected}} -> assert actual == expected
        {{:error, _}, %{"expected_error" => _}} -> :ok
        {result, _} -> flunk("unexpected #{inspect(result)}")
      end
    end
  end
end
