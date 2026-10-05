defmodule RelayMark.ContentEditProducerTest do
  use ExUnit.Case, async: true
  @root Path.expand("../../../spec/relaymark/collaboration/fixtures", __DIR__)

  test "shipped DOM-free runtime emits exact rich command bytes and generated suffix evidence" do
    fixture = File.read!(Path.join(@root, "content-edit-enter-mutation.json")) |> Jason.decode!()
    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)

    input = %{
      "state_base64" => fixture["sender_state_base64"],
      "writer_client" => fixture["writer_client"],
      "transaction_id" => "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "owner_id" => "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      "steps" => fixture["operation"]["steps"]
    }

    assert {:ok, result} = RelayMark.ContentEdit.produce(runtime, input)
    assert result["text_items"] == %{"runs" => []}

    assert Enum.sum(
             for copy <- result["content_edit"]["copies"],
                 run <- copy["destination"]["runs"],
                 do: run["count"]
           ) == 16

    assert result["proof"]["footprint"] == fixture["footprint"]
    assert result["proof"]["complete_mutation_correspondence"]

    assert result["content_edit"]["group"] == %{
             "owner_id" => input["owner_id"],
             "reference" => input["transaction_id"],
             "operation_ids" => [input["transaction_id"]]
           }

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.produce(runtime, Map.put(input, "steps", []))

    assert {:ok, ^result} = RelayMark.ContentEdit.produce(runtime, input)
  end
end
