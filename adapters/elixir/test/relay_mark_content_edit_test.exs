defmodule RelayMark.ContentEditTest do
  use ExUnit.Case, async: true

  test "server applies actual rich paste steps through maintained PM in the same schema" do
    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)

    before = %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "paragraph",
          "attrs" => %{"relaymarkId" => "b11111111111141118111111111111111"},
          "content" => [%{"type" => "text", "text" => "Hello world"}]
        }
      ]
    }

    operation = %{
      "kind" => "content_edit",
      "steps" => [
        %{
          "stepType" => "replace",
          "from" => 7,
          "to" => 12,
          "slice" => %{
            "content" => [
              %{"type" => "text", "text" => "peer", "marks" => [%{"type" => "bold"}]},
              %{"type" => "text", "text" => "!", "marks" => [%{"type" => "italic"}]}
            ]
          }
        }
      ]
    }

    assert {:ok, result} = RelayMark.ContentEdit.apply(runtime, before, operation)
    assert result["step_maps"] == [%{"ranges" => [7, 5, 5], "inverted" => false}]

    assert hd(result["authored_document"]["blocks"])["content"] == [
             %{"type" => "text", "text" => "Hello "},
             %{"type" => "strong", "content" => [%{"type" => "text", "text" => "peer"}]},
             %{"type" => "emphasis", "content" => [%{"type" => "text", "text" => "!"}]}
           ]

    ast = %{
      "type" => "relaymark.document",
      "blocks" => [
        %{
          "id" => "b11111111111141118111111111111111",
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Hello world"}]
        }
      ],
      "frontmatter" => %{},
      "annotations" => [],
      "resources" => [],
      "meta" => %{"origin" => "same-owner"}
    }

    assert {:ok, portable} = RelayMark.ContentEdit.apply_document(runtime, ast, operation)

    assert portable["authored_document"] ==
             Map.put(ast, "blocks", result["authored_document"]["blocks"])

    invalid =
      put_in(operation, ["steps", Access.at(0), "slice", "content", Access.at(0), "attrs"], %{
        "hidden" => true
      })

    assert {:error, _reason} = RelayMark.ContentEdit.apply(runtime, before, invalid)
    assert {:ok, ^result} = RelayMark.ContentEdit.apply(runtime, before, operation)
  end

  test "real rich Enter causal preparation refuses omitted copied suffix and hidden allocation" do
    fixture =
      Path.expand(
        "../../../spec/relaymark/collaboration/fixtures/content-edit-enter-witness.json",
        __DIR__
      )
      |> File.read!()
      |> Jason.decode!()

    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)
    assert {:ok, result} = RelayMark.ContentEdit.prepare_witness(runtime, fixture["evidence"])
    for {key, expected} <- fixture["expected"], do: assert(result[key] == expected)
    assert result["requires_mutation_correspondence"]
    assert result["unproven_mutations"]["structs"] != []

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.prepare_witness(
               runtime,
               Map.delete(fixture["evidence"], "footprint")
             )

    omitted = put_in(fixture, ["evidence", "operation", "copies"], [])

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.prepare_witness(runtime, omitted["evidence"])
  end

  test "QuickJS execution interrupts runaway evaluation at 100ms and remains usable" do
    # Canonical bundle initialization is covered above at the production budget.
    # Isolate the interpreter's execution budget from loading that bundle.
    assert {:ok, runtime} = Quicksand.start(timeout: 100)
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)
    assert {:error, "timeout"} = Quicksand.eval(runtime, "while(true) {}")
    assert {:ok, 42} = Quicksand.eval(runtime, "42")
  end

  test "packaged source classifier preserves partial tombstoned ancestry and refuses a forged text branch" do
    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)
    binding = %{"document_id" => "document", "incarnation" => "incarnation"}

    selector = fn clock, count, type ->
      %{
        "runs" => [
          %{
            "item" => %{"client" => 101, "clock" => clock},
            "type" => %{"client" => 101, "clock" => type},
            "count" => count
          }
        ]
      }
    end

    copies = [%{"source" => selector.(11, 16, 2), "destination" => selector.(53, 16, 2)}]

    transaction = %{
      "transaction_id" => "22222222-2222-4222-8222-222222222222",
      "text_items" => %{"runs" => []},
      "content_edit" => %{"history" => %{}, "copies" => copies}
    }

    proof = %{
      "complete_mutation_correspondence" => true,
      "owned_history_correspondence" => true,
      "text_items" => %{"runs" => []},
      "proven_copies" => copies,
      "restored_copies" => copies
    }

    assert {:ok, reference} =
             RelayMark.ContentEdit.classify_source_reference(
               runtime,
               binding,
               transaction,
               proof,
               selector.(11, 4, 2)
             )

    assert reference["human_destinations"] == selector.(53, 4, 2)

    assert {:ok, human} =
             RelayMark.ContentEdit.fold_source_references(
               runtime,
               binding,
               selector.(53, 16, 2),
               [reference]
             )

    assert human == selector.(53, 4, 2)

    assert {:error, :source_reference_mismatch} =
             RelayMark.ContentEdit.fold_source_references(
               runtime,
               %{"document_id" => "document", "incarnation" => "other"},
               selector.(53, 16, 2),
               [reference]
             )

    assert {:error, :source_identity_limit} =
             RelayMark.ContentEdit.fold_source_references(
               runtime,
               binding,
               selector.(0, 131_073, 2),
               []
             )

    assert {:error, :source_identity_mismatch} =
             RelayMark.ContentEdit.classify_source_reference(
               runtime,
               binding,
               transaction,
               proof,
               selector.(11, 4, 999)
             )
  end

  test "the supported maximum copied source command fits bounded runtime resources" do
    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)

    select = fn clock ->
      %{
        "runs" => [
          %{
            "item" => %{"client" => 101, "clock" => clock},
            "type" => %{"client" => 101, "clock" => 2},
            "count" => 131_072
          }
        ]
      }
    end

    source = select.(100)
    destination = select.(200_000)
    copies = [%{"source" => source, "destination" => destination}]

    transaction = %{
      "transaction_id" => "33333333-3333-4333-8333-333333333333",
      "text_items" => %{"runs" => []},
      "content_edit" => %{"copies" => copies}
    }

    proof = %{
      "complete_mutation_correspondence" => true,
      "text_items" => %{"runs" => []},
      "proven_copies" => copies
    }

    assert {:ok, %{"human_destinations" => ^destination} = reference} =
             RelayMark.ContentEdit.classify_source_reference(
               runtime,
               %{"document_id" => "doc", "incarnation" => "inc"},
               transaction,
               proof,
               source
             )

    assert {:ok, ^destination} =
             RelayMark.ContentEdit.fold_source_references(
               runtime,
               %{"document_id" => "doc", "incarnation" => "inc"},
               destination,
               [reference]
             )

    overflow = put_in(source, ["runs", Access.at(0), "count"], 131_073)

    assert {:error, :source_identity_limit} =
             RelayMark.ContentEdit.classify_source_reference(
               runtime,
               %{"document_id" => "doc", "incarnation" => "inc"},
               transaction,
               proof,
               overflow
             )
  end

  test "shipped planner retains actual command dependencies through cold checkpoint and refuses forged cut" do
    fixture =
      Path.expand(
        "../../../spec/relaymark/collaboration/fixtures/content-edit-enter-inverse-history.json",
        __DIR__
      )
      |> File.read!()
      |> Jason.decode!()

    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime()
    on_exit(fn -> RelayMark.ContentEdit.stop_runtime(runtime) end)
    initial = fixture["undo"]["initial_state_base64"]
    owner = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    transaction = "91919191-9191-4191-8191-919191919191"
    hash = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end

    assert {:ok, command} =
             RelayMark.ContentEdit.produce(runtime, %{
               "state_base64" => initial,
               "writer_client" => 707,
               "owner_id" => owner,
               "transaction_id" => transaction,
               "steps" => [
                 %{
                   "stepType" => "replace",
                   "from" => 2,
                   "to" => 2,
                   "slice" => %{"content" => [%{"type" => "text", "text" => "New Ω "}]}
                 }
               ]
             })

    receipt = %{
      "transaction_id" => transaction,
      "sender_state_base64" => initial,
      "update_base64" => command["update_base64"],
      "operation" =>
        Map.put(
          Map.take(command["content_edit"], ["steps", "copies", "group"]),
          "kind",
          "content_edit"
        )
    }

    scope = %{"actor_id" => "synthetic-actor", "owner_id" => owner}
    basis = Map.merge(scope, %{"initial_state_base64" => initial, "receipts" => [receipt]})
    # Synthetic qualifiers test the packaged semantic seam, never donor authority.
    association =
      Map.merge(scope, %{
        "transaction_id" => transaction,
        "transaction_sha256" => hash.(Jason.encode!(receipt)),
        "update_sha256" => hash.(Base.decode64!(command["update_base64"])),
        "issued_reference_sha256" => hash.("synthetic-issued-reference")
      })

    input = %{
      "binding" => %{
        "document_id" => "22222222-2222-4222-8222-222222222222",
        "incarnation" => "33333333-3333-4333-8333-333333333333"
      },
      "current_state_base64" => command["state_base64"],
      "current_cut" => %{
        "through_update_id" => 1,
        "state_sha256" => hash.(Base.decode64!(command["state_base64"]))
      },
      "expected_manager_scopes" => [scope],
      "manager_contexts" => [basis],
      "imports" => [
        %{
          "receipt" => association,
          "imported_items" =>
            Enum.map(command["proof"]["footprint"]["structs"], &Map.take(&1, ["item", "count"]))
        }
      ]
    }

    assert {:ok, planned} =
             RelayMark.ContentEdit.plan_reviewed_recovery_retirement(runtime, input)

    assert planned["complete_dependency_correspondence"]
    assert hd(planned["associations"])["source_dependencies"] == command["text_items"]

    assert hd(hd(planned["associations"])["retirements"])["groups"] == [
             command["content_edit"]["group"]
           ]

    assert {:ok, checkpoint} =
             RelayMark.ContentEdit.checkpoint_owned_history(
               runtime,
               Map.put(
                 Map.delete(basis, "actor_id"),
                 "current_state_base64",
                 command["state_base64"]
               )
             )

    cold =
      Map.merge(input, %{
        "imports" => [],
        "dependency_checkpoint" => planned["dependency_checkpoint"],
        "checkpoint_state_base64" => command["state_base64"],
        "manager_contexts" => [Map.merge(scope, %{"checkpoint" => checkpoint, "receipts" => []})]
      })

    assert {:ok, restored} =
             RelayMark.ContentEdit.plan_reviewed_recovery_retirement(runtime, cold)

    assert restored["associations"] == planned["associations"]

    forged =
      put_in(input, ["imports", Access.at(0), "imported_items"], [
        %{"item" => %{"client" => 101, "clock" => 0}, "count" => 1}
      ])

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.plan_reviewed_recovery_retirement(runtime, forged)

    assert {:error, :invalid_content_edit} =
             RelayMark.ContentEdit.plan_reviewed_recovery_retirement(
               runtime,
               Map.delete(cold, "dependency_checkpoint")
             )
  end
end
