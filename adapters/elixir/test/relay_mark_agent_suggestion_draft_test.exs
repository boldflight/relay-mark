defmodule RelayMarkAgentSuggestionDraftTest do
  use ExUnit.Case, async: true

  alias RelayMark.AgentSuggestion

  @fixture Path.expand(
             "../../../spec/relaymark/collaboration/fixtures/agent-suggestion-v3-draft.json",
             __DIR__
           )

  test "real TipTap/Yjs fixture projects authored suggestion only" do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    attrs = fixture["normalized"]["content"] |> Enum.at(1) |> Map.fetch!("attrs")
    block = fixture["expected_ast"]["blocks"] |> Enum.at(1)

    assert {:ok, ^block} = AgentSuggestion.to_block(attrs)
    assert AgentSuggestion.valid_block?(block)
    refute Map.has_key?(attrs, "proposalId")
    refute Map.has_key?(attrs, "source")
  end

  test "host action fields and invalid authored states fail closed" do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    attrs = fixture["normalized"]["content"] |> Enum.at(1) |> Map.fetch!("attrs")

    for extra <- [
          %{"proposalId" => "host"},
          %{"proposalStatus" => "accepted"},
          %{"title" => "host"},
          %{"undoable" => true},
          %{"source" => "source"}
        ] do
      assert :error == AgentSuggestion.to_block(Map.merge(attrs, extra))
    end

    assert :error == AgentSuggestion.to_block(%{attrs | "review" => "accepted"})
    assert :error == AgentSuggestion.to_block(%{attrs | "confidence" => 1.1})
    assert :error == AgentSuggestion.to_block(%{attrs | "content" => " unnormalized"})

    assert :error ==
             AgentSuggestion.to_block(%{attrs | "evidence" => ["duplicate", "duplicate"]})
  end
end
