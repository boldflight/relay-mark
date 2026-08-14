defmodule RelayMark.ManifestProjection do
  @moduledoc false

  @commonmark_inline_types ~w(text hard_break soft_break link emphasis strong code_span)
  @block_reference_types ~w(relay.evidence_ref relay.file_ref relay.note_ref relay.url_ref)
  @composition_capabilities %{
    "relay.entity_reference" => {"entity.reference", "plain_text"},
    "relay.property_sheet" => {"binding.property_sheet", "summary"},
    "relay.data_view" => {"binding.data_view", "summary"},
    "relay.layout" => {"layout.adaptive_columns", "children"}
  }

  @spec project(map(), [map()]) :: map()
  def project(document, diagnostics \\ []) when is_map(document) and is_list(diagnostics) do
    resources_by_id =
      document
      |> Map.get("resources", [])
      |> Map.new(&{&1["id"], &1})

    manifest = %{
      "type" => "relaymark.manifest",
      "version" => 1,
      "actions" => [],
      "mentions" => [],
      "references" => [],
      "forms" => [],
      "sources" => [],
      "claims" => [],
      "comparisons" => [],
      "diagnostics" => diagnostics
    }

    manifest =
      document
      |> Map.get("blocks", [])
      |> project_blocks(manifest, resources_by_id)

    manifest
    |> Map.update!("mentions", &Enum.uniq/1)
    |> Map.update!("references", &Enum.uniq/1)
  end

  defp project_blocks(blocks, manifest, resources_by_id) do
    Enum.reduce(blocks, manifest, fn block, acc ->
      acc = project_capability(block, acc)
      acc = project_block(block, acc, resources_by_id)
      acc = collect_inline_references(block, acc)
      child_blocks = Enum.filter(block["content"] || [], &block_node?/1)
      project_blocks(child_blocks, acc, resources_by_id)
    end)
  end

  defp project_capability(%{"type" => type, "id" => block_id}, manifest) do
    case @composition_capabilities[type] do
      {capability, fallback} ->
        append_optional(manifest, "capabilities", %{
          "block_id" => block_id,
          "id" => capability,
          "fallback" => fallback
        })

      nil ->
        manifest
    end
  end

  defp project_block(%{"type" => "relay.entity_reference"} = block, manifest, _resources) do
    props = block["props"] || %{}

    append_optional(
      manifest,
      "entity_references",
      compact(%{
        "block_id" => block["id"],
        "id" => props["id"],
        "label" => props["label"] || empty_to_nil(trim_relaymark_whitespace(plain_text(block))),
        "projection" => props["projection"] || "link"
      })
    )
  end

  defp project_block(%{"type" => "relay.property_sheet"} = block, manifest, _resources) do
    props = block["props"] || %{}

    append_optional(
      manifest,
      "property_sheets",
      compact(%{
        "block_id" => block["id"],
        "binding" => props["binding"],
        "fields" => props["fields"] || [],
        "title" => props["title"],
        "presentation" => props["presentation"] || "stack"
      })
    )
  end

  defp project_block(%{"type" => "relay.data_view"} = block, manifest, _resources) do
    props = block["props"] || %{}

    append_optional(
      manifest,
      "data_views",
      compact(%{
        "block_id" => block["id"],
        "source" => props["source"],
        "projection" => props["projection"],
        "columns" => props["columns"] || [],
        "filter" => props["filter"],
        "sort" => props["sort"] || [],
        "group" => props["group"],
        "limit" => props["limit"],
        "title" => props["title"]
      })
    )
  end

  defp project_block(%{"type" => "relay.layout"} = block, manifest, _resources) do
    props = block["props"] || %{}

    append_optional(
      manifest,
      "layouts",
      compact(%{
        "block_id" => block["id"],
        "mode" => props["mode"] || "one_column",
        "columns" => props["columns"],
        "label" => props["label"]
      })
    )
  end

  defp project_block(%{"type" => "relay.action_row"} = block, manifest, _resources_by_id) do
    props = block["props"] || %{}

    action =
      compact(%{
        "block_id" => block["id"],
        "proposal_id" => props["proposal_id"],
        "proposal_record_id" => props["proposal_record_id"],
        "proposal_revision" => props["proposal_revision"],
        "action" => props["action"],
        "target" => props["target"],
        "destination" => props["destination"],
        "visibility" => props["visibility"],
        "review" => props["review"],
        "decision_id" => props["decision_id"],
        "execution_id" => props["execution_id"],
        "undo_id" => props["undo_id"],
        "evidence_refs" => evidence_refs_for(block),
        "args" =>
          Map.put(
            props["args"] || %{},
            "title",
            block |> plain_text() |> trim_relaymark_whitespace()
          )
      })

    manifest = append(manifest, "actions", action)

    if is_binary(props["target"]) and String.starts_with?(props["target"], "entity:") do
      append(manifest, "mentions", %{
        "block_id" => block["id"],
        "kind" => "entity",
        "id" => String.replace_prefix(props["target"], "entity:", ""),
        "label" => props["target"]
      })
    else
      manifest
    end
  end

  defp project_block(%{"type" => "relay.claim"} = block, manifest, _resources_by_id) do
    props = block["props"] || %{}

    append(
      manifest,
      "claims",
      compact(%{
        "block_id" => block["id"],
        "key" => props["key"],
        "subject" => props["subject"],
        "status" => props["status"] || "unverified",
        "confidence" => props["confidence"],
        "evidence_refs" => evidence_refs_for(block),
        "text" => block |> plain_text() |> trim_relaymark_whitespace()
      })
    )
  end

  defp project_block(%{"type" => "relay.comparison"} = block, manifest, _resources_by_id) do
    props = block["props"] || %{}

    append(
      manifest,
      "comparisons",
      compact(%{
        "block_id" => block["id"],
        "title" => props["title"],
        "subjects" => props["subjects"] || [],
        "criteria" => props["criteria"] || [],
        "values" => props["values"] || %{},
        "preferred" => props["preferred"],
        "layout" => props["layout"] || "table",
        "evidence_refs" => evidence_refs_for(block),
        "summary" => block |> plain_text() |> trim_relaymark_whitespace()
      })
    )
  end

  defp project_block(%{"type" => "relay.form_question"} = block, manifest, _resources_by_id) do
    props = block["props"] || %{}

    append(
      manifest,
      "forms",
      compact(%{
        "block_id" => block["id"],
        "key" => props["key"],
        "label" => props["label"],
        "field_type" => props["field_type"],
        "required" => props["required"] || false,
        "options" => props["options"] || []
      })
    )
  end

  defp project_block(%{"type" => "relay.source_bundle"} = block, manifest, _resources_by_id) do
    props = block["props"] || %{}

    append(
      manifest,
      "sources",
      compact(%{
        "block_id" => block["id"],
        "kind" => "source_bundle",
        "source_id" => props["id"],
        "bundle_revision" => props["revision"],
        "source_hash" => props["source_hash"],
        "label" => props["title"]
      })
    )
  end

  defp project_block(%{"type" => "relay.evidence_ref"} = block, manifest, resources_by_id) do
    props = block["props"] || %{}
    source_resource = resources_by_id[props["source"]]

    scripture_release =
      if props["source_type"] == "scripture" and is_map(source_resource) and
           source_resource["type"] == "scripture" do
        source_resource["props"]
      end

    excerpt =
      block
      |> plain_text()
      |> trim_relaymark_whitespace()
      |> empty_to_nil()

    append(
      manifest,
      "sources",
      compact(%{
        "block_id" => block["id"],
        "kind" => "evidence_ref",
        "evidence_id" => props["id"],
        "source_id" => props["source"],
        "source_type" => props["source_type"],
        "source_revision" => props["source_revision"],
        "selector" => props["selector"],
        "scope" => props["scope"],
        "label" => props["label"],
        "excerpt" => excerpt,
        "scripture_release" => scripture_release
      })
    )
  end

  defp project_block(%{"type" => "relay.transcript_segment"} = block, manifest, _resources_by_id) do
    props = block["props"] || %{}

    append(
      manifest,
      "sources",
      compact(%{
        "block_id" => block["id"],
        "kind" => "transcript_range",
        "source_id" => props["source"],
        "start" => props["start"],
        "end" => props["end"],
        "label" => props["speaker"]
      })
    )
  end

  defp project_block(%{"type" => "relay.file_ref"} = block, manifest, _resources_by_id) do
    props = block["props"] || %{}

    append(
      manifest,
      "sources",
      compact(%{
        "block_id" => block["id"],
        "kind" => "file_ref",
        "source_id" => props["id"],
        "uri" => props["uri"],
        "label" => props["label"]
      })
    )
  end

  defp project_block(%{"type" => "relay.note_ref"} = block, manifest, _resources_by_id) do
    props = block["props"] || %{}

    append(
      manifest,
      "sources",
      compact(%{
        "block_id" => block["id"],
        "kind" => "note_ref",
        "source_id" => props["document"] || props["block"],
        "label" => props["label"]
      })
    )
  end

  defp project_block(%{"type" => "relay.url_ref"} = block, manifest, _resources_by_id) do
    props = block["props"] || %{}

    append(
      manifest,
      "sources",
      compact(%{
        "block_id" => block["id"],
        "kind" => "url_ref",
        "uri" => props["url"],
        "label" => props["label"]
      })
    )
  end

  defp project_block(_block, manifest, _resources_by_id), do: manifest

  defp collect_inline_references(block, manifest) do
    Enum.reduce(inline_nodes(block["content"] || []), manifest, fn inline, acc ->
      acc =
        if is_binary(inline["type"]) and String.starts_with?(inline["type"], "relay.") and
             String.ends_with?(inline["type"], "_ref") do
          append(
            acc,
            "references",
            compact(%{
              "block_id" => block["id"],
              "type" => inline["type"],
              "id" => inline["id"],
              "label" => inline["label"],
              "href" => inline["href"]
            })
          )
        else
          acc
        end

      if inline["type"] == "relay.entity_ref" do
        append(
          acc,
          "mentions",
          compact(%{
            "block_id" => block["id"],
            "kind" => "entity",
            "id" => inline["id"],
            "label" => inline["label"]
          })
        )
      else
        acc
      end
    end)
  end

  defp inline_nodes(nodes) do
    Enum.flat_map(nodes, fn node ->
      cond do
        not is_map(node) ->
          []

        block_node?(node) ->
          []

        inline_node?(node) ->
          [node | inline_nodes(node["content"] || [])]

        true ->
          inline_nodes(node["content"] || [])
      end
    end)
  end

  defp plain_text(node) when is_list(node), do: Enum.map_join(node, "", &plain_text/1)
  defp plain_text(%{"type" => "text"} = node), do: node["text"] || ""

  defp plain_text(%{"type" => "relay." <> type, "label" => label})
       when is_binary(label) do
    if String.ends_with?(type, "_ref"), do: label, else: ""
  end

  defp plain_text(%{"content" => content}) when is_list(content), do: plain_text(content)
  defp plain_text(_node), do: ""

  defp block_node?(node) when is_map(node) do
    is_binary(node["type"]) and not inline_node?(node)
  end

  defp block_node?(_node), do: false

  defp inline_node?(%{"type" => type}) when type in @commonmark_inline_types, do: true
  defp inline_node?(%{"type" => type}) when type in @block_reference_types, do: false

  defp inline_node?(%{"type" => "relay." <> type}) do
    String.ends_with?(type, "_ref")
  end

  defp inline_node?(_node), do: false

  defp evidence_refs_for(block) do
    cond do
      is_list(block["evidence_refs"]) and block["evidence_refs"] != [] ->
        block["evidence_refs"]

      is_list(get_in(block, ["props", "evidence"])) ->
        get_in(block, ["props", "evidence"])

      true ->
        []
    end
  end

  defp trim_relaymark_whitespace(value) do
    value
    |> String.to_charlist()
    |> Enum.drop_while(&relaymark_whitespace?/1)
    |> Enum.reverse()
    |> Enum.drop_while(&relaymark_whitespace?/1)
    |> Enum.reverse()
    |> List.to_string()
  end

  defp relaymark_whitespace?(codepoint)
       when codepoint in 0x0009..0x000D or codepoint in 0x2000..0x200A,
       do: true

  defp relaymark_whitespace?(codepoint)
       when codepoint in [
              0x0020,
              0x0085,
              0x00A0,
              0x1680,
              0x2028,
              0x2029,
              0x202F,
              0x205F,
              0x3000
            ],
       do: true

  defp relaymark_whitespace?(_codepoint), do: false

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
  defp append(manifest, key, value), do: Map.update!(manifest, key, &(&1 ++ [value]))

  defp append_optional(manifest, key, value),
    do: Map.update(manifest, key, [value], &(&1 ++ [value]))

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
