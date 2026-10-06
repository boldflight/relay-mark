defmodule RelayMark.ReviewedRecoveryTest do
  use ExUnit.Case, async: true

  test "packaged imported heading link plan retains the original encoded destination and target" do
    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)

    heading = %{
      "type" => "heading",
      "attrs" => %{
        "relaymarkId" => "b00000000000040008000000000000001",
        "level" => 1,
        "headingId" => "chapter"
      },
      "content" => [%{"type" => "text", "text" => "Donor 🌍"}]
    }

    paragraph = %{
      "type" => "paragraph",
      "attrs" => %{"relaymarkId" => "b00000000000040008000000000000002"},
      "content" => [
        %{
          "type" => "text",
          "text" => "Jump",
          "marks" => [
            %{
              "type" => "link",
              "attrs" => %{
                "href" => "#%63hapter",
                "title" => "Kept title",
                "target" => "_blank",
                "rel" => "noopener noreferrer nofollow",
                "class" => nil
              }
            }
          ]
        }
      ]
    }

    target = put_in(heading, ["content"], [%{"type" => "text", "text" => "Target"}])
    before = %{"type" => "doc", "content" => [target]}

    input = %{
      "archive_document" => %{"type" => "doc", "content" => [heading, paragraph]},
      "before_document" => before,
      "block_indices" => [0, 1],
      "steps" => [
        %{
          "stepType" => "replace",
          "from" => 8,
          "to" => 8,
          "slice" => %{"content" => [heading, paragraph]}
        },
        %{
          "stepType" => "attr",
          "pos" => 8,
          "attr" => "headingId",
          "value" => "h-44444444-4444-4444-8444-444444444444"
        }
      ]
    }

    assert {:ok, planned} = RelayMark.ContentEdit.plan_reviewed_heading_navigation(runtime, input)
    assert Enum.map(planned["steps"], & &1["stepType"]) == ["removeMark", "addMark"]
    assert hd(planned["document"]["content"])["content"] == target["content"]
    [reference] = planned["navigation_correspondence"]["references"]

    assert reference == %{
             "source_path" => [1, 0],
             "kind" => "link",
             "source_target" => "#%63hapter",
             "destination_target" => "#h-44444444-4444-4444-8444-444444444444"
           }

    assert List.last(planned["steps"])["mark"]["attrs"]["title"] == "Kept title"

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.plan_reviewed_heading_navigation(runtime, %{
               input
               | "block_indices" => [1]
             })
  end

  test "packaged regional proof accounts imported Unicode without issuing human ancestry" do
    current = paragraph(1, "b00000000000040008000000000000001", "Current")
    imported = paragraph(2, "b00000000000040008000000000000002", "A🌍Z")
    archived = paragraph(3, "b00000000000040008000000000000003", "A🌍Z")
    before = %{"kind" => "fragment", "root" => "default", "children" => [current]}
    after_snapshot = %{before | "children" => [current, imported]}

    reviewed = %{
      "type" => "relaymark.document",
      "blocks" => [
        %{
          "id" => archived["attributes"]["relaymarkId"],
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "A🌍Z"}]
        }
      ]
    }

    step = %{
      "stepType" => "replace",
      "from" => 9,
      "to" => 9,
      "slice" => %{
        "content" => [
          %{
            "type" => "paragraph",
            "attrs" => imported["attributes"],
            "content" => [%{"type" => "text", "text" => "A🌍Z"}]
          }
        ]
      }
    }

    operation = %{
      "kind" => "content_edit",
      "copies" => [],
      "steps" => [step],
      "reviewed_recovery" => %{
        "archive_sha256" => String.duplicate("a", 64),
        "reviewed_document_sha256" => String.duplicate("b", 64),
        "block_indices" => [0],
        "target_guard" => %{"body_revision" => "sha256:" <> String.duplicate("c", 64)},
        "donor_cut" => nil
      }
    }

    footprint = %{
      "state_vector" => [%{"client" => 1, "clock" => 9}, %{"client" => 2, "clock" => 6}],
      "structs" => [
        %{
          "item" => %{"client" => 2, "clock" => 2},
          "count" => 4,
          "parent" => %{"type" => %{"client" => 2, "clock" => 1}},
          "key" => nil,
          "origin" => nil,
          "right_origin" => nil,
          "deleted" => false,
          "content" => %{"kind" => "string", "text" => "A🌍Z"}
        }
      ],
      "declared_deletes" => [],
      "deleted_items" => []
    }

    evidence = %{
      "sender_before_snapshot" => before,
      "sender_after_snapshot" => after_snapshot,
      "before_snapshot" => before,
      "after_snapshot" => after_snapshot,
      "before_state_vector" => [%{"client" => 1, "clock" => 9}],
      "operation" => operation,
      "footprint" => footprint,
      "archive_identity_snapshot" => %{before | "children" => [archived]},
      "reviewed_document" => reviewed
    }

    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)

    assert {:ok, result} =
             RelayMark.ContentEdit.prepare_reviewed_recovery_witness(runtime, evidence)

    assert result["text_items"] == %{"runs" => []}
    assert result["proven_copies"] == []

    assert [%{"archive_path" => [0, 0], "archive_offset" => 0, "count" => 4}] =
             Enum.map(
               result["recovery_regions"],
               &Map.take(&1, ~w(archive_path archive_offset count))
             )

    assert result["requires_recovery_authorization"] == true
    assert result["requires_mutation_correspondence"] == true
    refute Map.has_key?(result, "complete_mutation_correspondence")

    regional = %{
      "archive_identity_snapshot" => evidence["archive_identity_snapshot"],
      "recovery_regions" => result["recovery_regions"]
    }

    assert {:ok, source} =
             RelayMark.ContentEdit.reviewed_recovery_source_selection(runtime, regional)

    assert source == %{
             "runs" => [
               %{
                 "type" => %{"client" => 3, "clock" => 1},
                 "item" => %{"client" => 3, "clock" => 2},
                 "count" => 4
               }
             ]
           }

    human = %{
      "runs" => [
        %{
          "type" => %{"client" => 3, "clock" => 1},
          "item" => %{"client" => 3, "clock" => 3},
          "count" => 2
        }
      ]
    }

    assert {:ok, mapped} =
             RelayMark.ContentEdit.map_reviewed_recovery_selection(
               runtime,
               Map.put(regional, "source_selector", human)
             )

    assert mapped == %{
             "destination" => %{
               "runs" => [
                 %{
                   "type" => %{"client" => 2, "clock" => 1},
                   "item" => %{"client" => 2, "clock" => 3},
                   "count" => 2
                 }
               ]
             }
           }

    # This preliminary region proof cannot issue source authority without the
    # independently executed complete mutation proof at the admission owner.
    context = %{
      "recovery_regions" => result["recovery_regions"],
      "human_destinations" => mapped["destination"]
    }

    retained =
      evidence
      |> Map.drop(["archive_identity_snapshot", "reviewed_document"])
      |> Map.put("regional_context", context)

    assert {:ok, replayed} =
             RelayMark.ContentEdit.prepare_retained_reviewed_recovery_witness(runtime, retained)

    assert replayed["recovery_regions"] == result["recovery_regions"]
    assert replayed["fresh_items"] == result["fresh_items"]
    assert replayed["text_items"] == %{"runs" => []}
    assert replayed["proven_copies"] == []
    assert replayed["requires_mutation_correspondence"] == true
    refute Map.has_key?(replayed, "complete_mutation_correspondence")

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.prepare_retained_reviewed_recovery_witness(
               runtime,
               put_in(retained, ["regional_context", "recovery_regions"], [])
             )

    transaction = %{
      "transaction_id" => "22222222-2222-4222-8222-222222222222",
      "text_items" => result["text_items"],
      "content_edit" => operation
    }

    binding = %{"document_id" => "target", "incarnation" => "incarnation"}

    assert {:error, :source_reference_mismatch} =
             RelayMark.ContentEdit.classify_source_reference(
               runtime,
               binding,
               transaction,
               result,
               %{"runs" => []},
               context
             )

    assert {:ok, partition} =
             RelayMark.ContentEdit.partition_reviewed_recovery_destinations(
               runtime,
               Map.put(context, "generated_destinations", %{"runs" => []})
             )

    assert partition["human_destinations"] == mapped["destination"]
    assert partition["generated_destinations"] == %{"runs" => []}

    assert Enum.map(
             partition["unknown_destinations"]["runs"],
             &{&1["item"]["clock"], &1["count"]}
           ) == [{2, 1}, {5, 1}]

    assert {:error, :source_reference_mismatch} =
             RelayMark.ContentEdit.partition_reviewed_recovery_destinations(
               runtime,
               Map.put(context, "generated_destinations", mapped["destination"])
             )

    bad = put_in(human, ["runs", Access.at(0), "type", "clock"], 0)

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.map_reviewed_recovery_selection(
               runtime,
               Map.put(regional, "source_selector", bad)
             )

    forged =
      put_in(
        evidence,
        [
          "operation",
          "steps",
          Access.at(0),
          "slice",
          "content",
          Access.at(0),
          "content",
          Access.at(0),
          "text"
        ],
        "B🌍Z"
      )

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.prepare_reviewed_recovery_witness(runtime, forged)
  end

  test "packaged actual checkpoint retires only the complete authenticated owned group" do
    fixture =
      Path.expand(
        "../../../spec/relaymark/collaboration/fixtures/content-edit-enter-inverse-history.json",
        __DIR__
      )
      |> File.read!()
      |> Jason.decode!()

    undo = fixture["undo"]
    owner = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

    receipts =
      Enum.map(undo["receipts"], fn receipt ->
        update_in(receipt, ["operation", "group"], &Map.put(&1, "owner_id", owner))
      end)

    args = %{
      "initial_state_base64" => undo["initial_state_base64"],
      "receipts" => receipts,
      "current_state_base64" => undo["current_state_base64"],
      "owner_id" => owner,
      "groups" => [hd(receipts)["operation"]["group"]]
    }

    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)
    assert {:ok, result} = RelayMark.ContentEdit.retire_owned_history(runtime, args)
    assert result["undo"] == 1
    assert result["redo"] == 0
    assert result["checkpoint"]["undo_stack"] == []
    assert result["retired_groups"] == args["groups"]
    refute Map.has_key?(result, "update_base64")

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.retire_owned_history(runtime, %{
               args
               | "groups" => [
                   Map.put(hd(args["groups"]), "owner_id", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
                 ]
             })
  end

  defp paragraph(client, id, text) do
    count =
      text |> :unicode.characters_to_binary(:utf8, {:utf16, :little}) |> byte_size() |> div(2)

    %{
      "kind" => "element",
      "type" => %{"client" => client, "clock" => 0},
      "name" => "paragraph",
      "attributes" => %{"relaymarkId" => id},
      "children" => [
        %{
          "kind" => "text",
          "type" => %{"client" => client, "clock" => 1},
          "runs" => [
            %{
              "item" => %{"client" => client, "clock" => 2},
              "count" => count,
              "text" => text,
              "attributes" => %{}
            }
          ]
        }
      ]
    }
  end
end
