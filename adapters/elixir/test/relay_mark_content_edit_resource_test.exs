defmodule RelayMark.ContentEditResourceTest do
  # This case consumes the full native-runtime resource budget. Run it after
  # async cases so competing test runtimes do not consume its wall-clock budget.
  # Production limits, maximum input and all rejection assertions stay exact.
  use ExUnit.Case, async: false

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
end
