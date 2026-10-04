defmodule RelayMark.ContentEditMutationTest do
  use ExUnit.Case, async: true
  @root Path.expand("../../../spec/relaymark/collaboration/fixtures", __DIR__)
  for name <- ~w(enter peer typing mark widget delete redundant) do
    test "actual #{name} command retains complete maintained allocation and deletion correspondence" do
      evidence =
        File.read!(Path.join(@root, "content-edit-#{unquote(name)}-mutation.json"))
        |> Jason.decode!()
        |> Map.delete("description")

      assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
      on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)
      assert {:ok, result} = RelayMark.ContentEdit.replay_mutation(runtime, evidence)
      assert result["complete_mutation_correspondence"] == true

      unless unquote(name) == "redundant",
        do: assert(result["footprint"] == evidence["footprint"])

      assert {:error, :invalid_content_edit} =
               RelayMark.ContentEdit.replay_mutation(
                 runtime,
                 Map.put(evidence, "writer_client", 999)
               )
    end
  end

  for name <- ~w(transient-format transient-metadata) do
    test "hidden #{name} mutation is not an executed command consequence" do
      evidence =
        File.read!(Path.join(@root, "content-edit-#{unquote(name)}-mutation.json"))
        |> Jason.decode!()
        |> Map.delete("description")

      assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
      on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)

      assert {:error, :invalid_content_edit} =
               RelayMark.ContentEdit.replay_mutation(runtime, evidence)
    end
  end

  test "actual maintained marked owner group restores through undo and redo with peer choice retained" do
    fixture =
      File.read!(Path.join(@root, "content-edit-owned-mark-history.json")) |> Jason.decode!()

    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)

    for key <- ~w(undo redo) do
      assert {:ok, result} =
               RelayMark.ContentEdit.replay_mutation(
                 runtime,
                 fixture[key] |> known_manager_scope()
               )

      assert result["owned_history_correspondence"] == true
      assert result["footprint"] == fixture[key]["footprint"]
      assert is_list(result["restored_copies"])
      assert is_list(result["retained_field_changes"]["allocated"])
    end
  end

  test "explicit rich Slice source IDs can repeat while exact fresh destinations remain disjoint" do
    fixture =
      File.read!(Path.join(@root, "content-edit-duplicated-slice-witness.json"))
      |> Jason.decode!()

    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)
    input = Map.delete(fixture["evidence"], "text_items")
    assert {:ok, built} = RelayMark.ContentEdit.build_witness(runtime, input)
    assert built["proven_copies"] == fixture["expected"]["proven_copies"]
    assert built["text_items"] == %{"runs" => []}
    assert built["inserted_ranges"] == fixture["expected"]["inserted_ranges"]
    assert {:ok, replayed} = RelayMark.ContentEdit.replay_mutation(runtime, fixture["mutation"])
    assert replayed["complete_mutation_correspondence"] == true
  end

  test "authored body and doc metadata share exact maintained replay and peer-preserving owned inverse" do
    fixture =
      File.read!(Path.join(@root, "content-edit-metadata-history.json")) |> Jason.decode!()

    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)
    normal = Map.drop(fixture["normal"], ~w(before_snapshot_base64 update_base64 text_items))
    assert {:ok, result} = RelayMark.ContentEdit.replay_mutation(runtime, normal)
    assert result["complete_mutation_correspondence"] == true

    assert Enum.any?(
             result["retained_field_changes"]["allocated"],
             &(&1["parent"] == %{"root" => "relaymark"})
           )

    for effect <- fixture["effects"] do
      assert {:ok, result} = RelayMark.ContentEdit.replay_mutation(runtime, effect["evidence"])
      assert result["owned_history_correspondence"] == true
      assert result["text_items"] == %{"runs" => []}
      assert result["proven_copies"] == effect["proven_copies"]
    end
  end

  # This retained fixture predates the owner namespace. The test supplies its
  # independently known single manager; original CRDT/receipt bytes stay exact.
  defp known_manager_scope(evidence) do
    owner = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

    operation = fn operation ->
      key = if Map.has_key?(operation, "history"), do: "history", else: "group"
      Map.update!(operation, key, &Map.put(&1, "owner_id", owner))
    end

    evidence
    |> Map.update!("operation", operation)
    |> Map.update!("receipts", fn rows ->
      Enum.map(rows, &Map.update!(&1, "operation", operation))
    end)
  end
end
