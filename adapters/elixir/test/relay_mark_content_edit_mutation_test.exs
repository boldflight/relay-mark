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
end
