defmodule RelayMark.ContentEditCheckpointTest do
  use ExUnit.Case, async: true
  @root Path.expand("../../../spec/relaymark/collaboration/fixtures", __DIR__)
  @owner "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

  test "shipped maintained owner checkpoint resumes actual inverse without storing its original payloads" do
    fixture =
      File.read!(Path.join(@root, "content-edit-enter-inverse-history.json")) |> Jason.decode!()

    undo = fixture["undo"] |> known_owner()
    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)

    input = %{
      "initial_state_base64" => undo["initial_state_base64"],
      "receipts" => undo["receipts"],
      "current_state_base64" => undo["current_state_base64"],
      "owner_id" => @owner
    }

    assert {:ok, checkpoint} = RelayMark.ContentEdit.checkpoint_owned_history(runtime, input)
    assert length(checkpoint["undo_stack"]) == 1
    refute Jason.encode!(checkpoint) =~ "update_base64"

    evidence =
      undo
      |> Map.delete("initial_state_base64")
      |> Map.put("receipts", [])
      |> Map.put("checkpoint", checkpoint)

    assert {:ok, proof} = RelayMark.ContentEdit.replay_mutation(runtime, evidence)
    assert proof["owned_history_correspondence"]
    assert proof["text_items"] == %{"runs" => []}

    assert Enum.sum(
             for copy <- proof["proven_copies"],
                 run <- copy["destination"]["runs"],
                 do: run["count"]
           ) == 16

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.replay_mutation(
               runtime,
               put_in(evidence, ["checkpoint", "retained"], [])
             )

    assert {:ok, ^proof} = RelayMark.ContentEdit.replay_mutation(runtime, evidence)

    redo = fixture["redo"] |> known_owner()

    assert {:ok, second_cut} =
             RelayMark.ContentEdit.checkpoint_owned_history(runtime, %{
               "checkpoint" => checkpoint,
               "receipts" => Enum.drop(redo["receipts"], length(undo["receipts"])),
               "current_state_base64" => redo["current_state_base64"],
               "owner_id" => @owner
             })

    assert second_cut["undo_stack"] == []
    assert length(second_cut["redo_stack"]) == 1
    assert second_cut["redone"] != []

    redo_evidence =
      redo
      |> Map.delete("initial_state_base64")
      |> Map.put("receipts", [])
      |> Map.put("checkpoint", second_cut)

    assert {:ok, redo_proof} = RelayMark.ContentEdit.replay_mutation(runtime, redo_evidence)
    assert redo_proof["owned_history_correspondence"]
    assert redo_proof["text_items"] == %{"runs" => []}

    assert Enum.sum(
             for copy <- redo_proof["proven_copies"],
                 run <- copy["destination"]["runs"],
                 do: run["count"]
           ) == 16
  end

  defp known_owner(evidence) do
    evidence = put_in(evidence, ["operation", "history", "owner_id"], @owner)

    Map.update!(evidence, "receipts", fn receipts ->
      Enum.map(receipts, fn receipt ->
        key = if receipt["operation"]["history"], do: "history", else: "group"
        put_in(receipt, ["operation", key, "owner_id"], @owner)
      end)
    end)
  end
end
