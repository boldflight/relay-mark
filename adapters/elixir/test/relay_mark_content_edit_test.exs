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

  test "maintained runtime interrupts runaway evaluation and remains usable" do
    assert {:ok, runtime} = RelayMark.ContentEdit.start_runtime(timeout: 100)
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

    assert {:ok, %{"human_destinations" => ^destination}} =
             RelayMark.ContentEdit.classify_source_reference(
               runtime,
               %{"document_id" => "doc", "incarnation" => "inc"},
               transaction,
               proof,
               source
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
end
