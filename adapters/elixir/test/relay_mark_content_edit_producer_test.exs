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

  test "shipped reviewed target planner preserves rich form identities while appending prose and metadata" do
    fixture = File.read!(Path.join(@root, "content-edit-typing-mutation.json")) |> Jason.decode!()

    target = %{
      "type" => "relaymark.document",
      "frontmatter" => %{"title" => "Reviewed title"},
      "blocks" => [
        %{
          "id" => "b2e875b829a8d449d8add8f4dff412bcc",
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "A🌍Z"}]
        },
        %{
          "id" => "bc7bce8feedb949c58e23ba01ba4bfcf1",
          "type" => "relay.form_question",
          "props" => %{
            "required" => false,
            "points" => nil,
            "min" => nil,
            "max" => nil,
            "settings" => %{},
            "id" => "q-one",
            "type" => "multiple_choice"
          },
          "content" => [
            %{
              "id" => "bb81892eef8944b448aa3d6d6b45378cb",
              "type" => "paragraph",
              "content" => [
                %{"type" => "strong", "content" => [%{"type" => "text", "text" => "Choose"}]}
              ]
            },
            %{
              "id" => "b377a9245a2a740e88155585700257f6f",
              "type" => "relay.form_option",
              "props" => %{"correct" => false, "points" => nil, "settings" => %{}, "id" => "one"},
              "content" => [%{"type" => "text", "text" => "One"}]
            },
            %{
              "id" => "bbe202601843d41d0872ed95eaa250d3c",
              "type" => "relay.form_option",
              "props" => %{"correct" => false, "points" => nil, "settings" => %{}, "id" => "two"},
              "content" => [%{"type" => "text", "text" => "Two"}]
            }
          ]
        },
        %{
          "id" => "b88888888888848888888888888888888",
          "type" => "paragraph",
          "content" => [
            %{"type" => "strong", "content" => [%{"type" => "text", "text" => "Reviewed 🌍"}]}
          ]
        }
      ]
    }

    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)

    input = %{
      "state_base64" => fixture["sender_state_base64"],
      "writer_client" => 818,
      "transaction_id" => "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "owner_id" => "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      "target_document" => target
    }

    assert {:ok, result} = RelayMark.ContentEdit.produce_document_patch(runtime, input)
    assert result["authored_document"] == target
    assert result["proof"]["complete_mutation_correspondence"]
    assert Enum.count(result["content_edit"]["steps"], &(&1["stepType"] == "docAttr")) == 1
    assert Enum.sum(for run <- result["text_items"]["runs"], do: run["count"]) == 11
    assert {:ok, ^result} = RelayMark.ContentEdit.produce_document_patch(runtime, input)

    required = put_in(target, ["blocks", Access.at(1), "props", "required"], true)

    assert {:ok, next} =
             RelayMark.ContentEdit.produce_document_patch(runtime, %{
               input
               | "state_base64" => result["state_base64"],
                 "target_document" => required,
                 "transaction_id" => "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
             })

    assert next["content_edit"]["steps"] == [
             %{"stepType" => "attr", "pos" => 6, "attr" => "required", "value" => true}
           ]

    assert next["text_items"] == %{"runs" => []}
    assert next["content_edit"]["copies"] == []
    assert next["authored_document"] == required
    assert next["proof"]["complete_mutation_correspondence"]

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.produce_document_patch(
               runtime,
               Map.put(input, "target_document", Map.put(target, "unknown", "discard me"))
             )
  end
end
