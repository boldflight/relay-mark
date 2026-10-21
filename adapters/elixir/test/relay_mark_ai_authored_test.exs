defmodule RelayMark.AiAuthoredTest do
  use ExUnit.Case, async: true

  # Shared with the JavaScript runtime: one meaning of an agent-written run.
  @fixture Path.expand(
             "../../../spec/relaymark/collaboration/fixtures/ai-authored-mark.json",
             __DIR__
           )
           |> File.read!()
           |> Jason.decode!()

  test "ai_authored round-trips through the Yjs snapshot, renders marked and leaves only the words in Markdown" do
    ast = @fixture["ast"]
    assert {:ok, snapshot} = RelayMark.DocumentXML.from_document(ast)

    [%{"children" => [%{"delta" => runs}]}] = snapshot["children"]
    run_id = "4f1c2b7a-5d6e-4f80-9a1b-2c3d4e5f6a7b"

    assert Enum.map(runs, & &1["attributes"]) == [
             %{},
             %{"bold" => %{}, "ai_authored" => %{"run_id" => run_id}},
             %{"ai_authored" => %{"run_id" => run_id}}
           ]

    assert {:ok, ^ast} = RelayMark.DocumentXML.to_document(snapshot)
    assert RelayMark.render_document(ast) == {:ok, @fixture["html"]}
    assert RelayMark.project_document_markdown(ast) == {:ok, @fixture["markdown"]}
  end

  test "a peer's ai_authored run must name its run" do
    {:ok, snapshot} = RelayMark.DocumentXML.from_document(@fixture["ast"])

    for broken <- [
          %{"run_id" => ""},
          %{},
          %{"run_id" => 7},
          %{"run_id" => String.duplicate("r", 65)}
        ] do
      tampered =
        put_in(
          snapshot,
          [
            "children",
            Access.at(0),
            "children",
            Access.at(0),
            "delta",
            Access.at(2),
            "attributes"
          ],
          %{"ai_authored" => broken}
        )

      assert {:error, _} = RelayMark.DocumentXML.to_document(tampered)
    end

    unnamed =
      update_in(
        @fixture["ast"],
        ["blocks", Access.at(0), "content", Access.at(2)],
        &Map.delete(&1, "run_id")
      )

    assert {:error, _} = RelayMark.DocumentXML.from_document(unnamed)
  end
end
