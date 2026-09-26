defmodule RelayMarkTaskListV3DraftTest do
  use ExUnit.Case, async: true

  alias RelayMark.Schema

  @fixture Path.expand(
             "../../../spec/relaymark/collaboration/fixtures/task-list-v3-draft.json",
             __DIR__
           )

  test "packaged schema and semantic validator accept the real TipTap/Yjs task-list AST" do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    ast = fixture["expected_ast"]

    assert :ok = Schema.validate_document_schema(ast)
    assert :ok = RelayMark.validate_document(ast)
    assert ["paragraph", "task_list", "paragraph"] == Enum.map(ast["blocks"], & &1["type"])

    [linked, unlinked] = ast["blocks"] |> Enum.at(1) |> Map.fetch!("content")
    assert linked["props"] == %{"checked" => true, "entityId" => fixture["linked_entity_id"]}
    assert unlinked["props"] == %{"checked" => false, "entityId" => nil}

    assert Enum.map(linked["content"], & &1["type"]) ==
             ["paragraph", "paragraph", "task_list", "list"]
  end

  test "task metadata and child grammar produce the same semantic diagnostics as JavaScript" do
    ast = @fixture |> File.read!() |> Jason.decode!() |> Map.fetch!("expected_ast")

    invalid_checked =
      put_in(ast, ["blocks", Access.at(1), "content", Access.at(0), "props", "checked"], 1)

    assert diagnostic_codes(invalid_checked) == ["relaymark.task_item.props"]

    invalid_entity =
      put_in(
        ast,
        ["blocks", Access.at(1), "content", Access.at(0), "props", "entityId"],
        "Task-1"
      )

    assert diagnostic_codes(invalid_entity) == ["relaymark.task_item.props"]

    invalid_child =
      put_in(
        ast,
        ["blocks", Access.at(1), "content", Access.at(0), "content", Access.at(0), "type"],
        "heading"
      )

    assert diagnostic_codes(invalid_child) == ["relaymark.task_item.children"]

    stale_metadata =
      put_in(
        ast,
        ["blocks", Access.at(1), "content", Access.at(0), "props", "lastText"],
        "shadow"
      )

    assert diagnostic_codes(stale_metadata) == ["relaymark.task_item.props"]

    absent_entity =
      update_in(
        ast,
        ["blocks", Access.at(1), "content", Access.at(0), "props"],
        &Map.delete(&1, "entityId")
      )

    assert diagnostic_codes(absent_entity) == ["relaymark.task_item.props"]
  end

  test "task-list nesting stops at the shared 16-level limit" do
    ast = @fixture |> File.read!() |> Jason.decode!() |> Map.fetch!("expected_ast")
    deep = put_in(ast, ["blocks", Access.at(1)], nested_task_list(0))
    assert diagnostic_codes(deep) == ["relaymark.task_list.children"]
  end

  defp nested_task_list(level) do
    content =
      [%{"id" => "taskParagraph#{level}", "type" => "paragraph", "content" => []}] ++
        if(level < 16, do: [nested_task_list(level + 1)], else: [])

    %{
      "id" => "taskList#{level}",
      "type" => "task_list",
      "content" => [
        %{
          "id" => "taskItem#{level}",
          "type" => "task_item",
          "props" => %{"checked" => false, "entityId" => nil},
          "content" => content
        }
      ]
    }
  end

  defp diagnostic_codes(document) do
    assert {:error, diagnostics} = RelayMark.validate_document(document)
    Enum.map(diagnostics, & &1["code"])
  end
end
