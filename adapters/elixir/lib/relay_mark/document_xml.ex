defmodule RelayMark.DocumentXML do
  @moduledoc """
  Canonical rich AST interchange with portable Yjs XML snapshots.
  Community Yjs/Yex/Yrs owns transactions and binary encodings. The host installs
  `children` in `default` and optional authored `metadata` in the `relaymark` map.
  This module never changes a live document or authorizes domain actions.
  """
  @ids ~r/^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$/
  @uuid ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
  @metadata ~w(frontmatter annotations resources meta)
  @marks [
    {"link", "link"},
    {"bold", "strong"},
    {"code", "code_span"},
    {"italic", "emphasis"},
    {"strike", "strikethrough"},
    {"underline", "underline"},
    {"highlight", "highlight"},
    {"superscript", "superscript"},
    {"subscript", "subscript"}
  ]
  @link_defaults %{
    "target" => "_blank",
    "rel" => "noopener noreferrer nofollow",
    "class" => nil,
    "title" => nil
  }
  @names %{
    "paragraph" => "paragraph",
    "heading" => "heading",
    "quote" => "blockquote",
    "list_item" => "listItem",
    "task_list" => "taskList",
    "task_item" => "taskItem",
    "code" => "codeBlock",
    "horizontal_rule" => "horizontalRule",
    "image" => "image",
    "table" => "table",
    "table_row" => "tableRow",
    "table_cell" => "tableCell",
    "relay.callout" => "callout",
    "relay.callout_title" => "calloutTitle",
    "relay.video_embed" => "videoEmbed",
    "relay.entity_reference" => "relayEntityReference",
    "relay.agent_suggestion" => "agentSuggestion",
    "relay.data_view" => "relayDataView",
    "relay.form_question" => "questionBlock",
    "relay.form_option" => "questionOption"
  }
  @fields %{
    "paragraph" => [],
    "questionLabel" => [],
    "calloutTitle" => [],
    "heading" => ~w(level headingId),
    "blockquote" => [],
    "bulletList" => [],
    "orderedList" => ~w(start type),
    "listItem" => [],
    "taskList" => [],
    "taskItem" => ~w(checked entityId),
    "codeBlock" => ~w(language),
    "horizontalRule" => [],
    "image" => ~w(src alt title width height),
    "table" => [],
    "tableRow" => [],
    "tableCell" => ~w(colspan rowspan colwidth align),
    "tableHeader" => ~w(colspan rowspan colwidth align),
    "callout" => ~w(tone emphasis),
    "videoEmbed" =>
      ~w(videoId source status playbackId title thumbnailUrl youtubeId uploadPercent),
    "relayEntityReference" => ~w(entityRef entityId entityType label projection source),
    "agentSuggestion" => ~w(review kind confidence evidence content),
    "relayDataView" => ~w(source projection columns filter sort group limit title),
    "questionBlock" => ~w(id type required points min max settings),
    "questionOption" => ~w(id correct points settings),
    "relayButton" => ~w(label kind target),
    "relayAnchor" => ~w(name),
    "relayConnection" => ~w(provider)
  }
  @names Map.merge(@names, RelayMark.DocumentDirectives.names())
  @fields Map.merge(@fields, RelayMark.DocumentDirectives.fields())
  @inline_names ~w(paragraph heading calloutTitle questionLabel questionOption codeBlock)
  @atom_names ~w(horizontalRule image videoEmbed relayEntityReference agentSuggestion relayDataView relayButton relayAnchor relayConnection)
  @question_types ~w(short_text long_text email phone number multiple_choice checkboxes dropdown linear_scale date file_upload page_break single_select multi_select entity_ref file slot_picker hidden_field calculated_field video_question video_response payment payment_block lightning_payment)

  def from_document(document) when is_map(document) do
    result(fn ->
      only!(document, ~w(type blocks) ++ @metadata)
      valid_document!(document)

      snapshot = %{
        "kind" => "fragment",
        "children" => Enum.map(document["blocks"], &encode_block/1)
      }

      metadata = Map.take(document, @metadata)

      snapshot = if metadata == %{}, do: snapshot, else: Map.put(snapshot, "metadata", metadata)
      # Strict inverse validates the rich grammar before any host installs it.
      decode_snapshot!(snapshot)
      snapshot
    end)
  end

  def from_document(_), do: error(:invalid_document)

  def to_document(snapshot) when is_map(snapshot),
    do: result(fn -> decode_snapshot!(snapshot) end)

  def to_document(_), do: error(:invalid_snapshot)

  defp decode_snapshot!(snapshot) do
    only!(snapshot, ~w(kind children metadata))
    require!(snapshot["kind"] == "fragment", :root)
    children = list!(snapshot["children"])
    require!(children != [], :empty_document)
    metadata = Map.get(snapshot, "metadata", %{})
    only!(metadata, @metadata)
    validate_json!(metadata, 0)
    nodes = descendant_blocks(children, 0)
    require!(length(nodes) <= 4096, :block_limit)

    ids =
      Enum.map(nodes, fn node -> attrs(node)["relaymarkId"] end)

    require!(Enum.all?(ids, &(is_binary(&1) and Regex.match?(@ids, &1))), :block_identity)
    require!(length(Enum.uniq(ids)) == length(ids), :duplicate_identity)
    blocks = Enum.map(children, &decode_block(&1, nil))
    document = Map.merge(metadata, %{"type" => "relaymark.document", "blocks" => blocks})
    valid_document!(document)
    validate_question_ids!(blocks)
    document
  end

  defp result(fun) do
    {:ok, fun.()}
  rescue
    _error in [KeyError, FunctionClauseError, ArgumentError, BadMapError, MatchError] ->
      error(:shape)
  catch
    {:invalid_document_xml, reason} -> error(reason)
  end

  defp error(reason),
    do:
      {:error,
       [
         %{
           "level" => "error",
           "code" => "relaymark.document_xml.invalid",
           "reason" => inspect(reason)
         }
       ]}

  defp require!(true, _), do: :ok
  defp require!(_, reason), do: throw({:invalid_document_xml, reason})

  defp only!(map, keys) when is_map(map),
    do: require!(Enum.all?(Map.keys(map), &(&1 in keys)), :unknown_fields)

  defp only!(_, _), do: require!(false, :object_required)
  defp list!(value) when is_list(value), do: value
  defp list!(_), do: require!(false, :array_required)

  defp valid_document!(document),
    do: require!(RelayMark.validate_document(document) == :ok, :invalid_ast)

  defp attrs(node) do
    require!(is_map(node["attributes"]), :block_identity)
    node["attributes"]
  end

  defp content(node), do: Map.get(node, "content", []) |> list!()

  defp element(name, attributes, children),
    do: %{"kind" => "element", "name" => name, "attributes" => attributes, "children" => children}

  defp encode_block(block) do
    only!(block, ~w(id type props content))
    type = block["type"]
    props = Map.get(block, "props", %{})

    {name, properties} =
      case type do
        "list" ->
          only!(props, ~w(kind start))
          require!(props["kind"] in ~w(bullet ordered), :list_kind)

          if props["kind"] == "ordered",
            do: {"orderedList", %{"start" => props["start"], "type" => nil}},
            else: {"bulletList", %{}}

        "table_cell" ->
          {if(props["header"], do: "tableHeader", else: "tableCell"), Map.delete(props, "header")}

        "relay.entity_reference" ->
          {:ok, fields} = RelayMark.EntityReference.parse_source(props["source"])
          require!(props == Map.take(fields, ~w(id label projection source)), :reference_source)

          {"relayEntityReference",
           %{
             "entityRef" => props["id"],
             "entityId" => fields["entityId"],
             "entityType" => "Entity",
             "label" => props["label"],
             "projection" => props["projection"],
             "source" => props["source"]
           }}

        "relay.paper_control" ->
          require!(RelayMark.PaperControl.valid_block?(block), :control_source)

          name =
            %{
              "button" => "relayButton",
              "anchor" => "relayAnchor",
              "connection" => "relayConnection"
            }[props["control"]]

          {name, Map.drop(props, ~w(control source))}

        "relay.agent_suggestion" ->
          {"agentSuggestion", Map.put(props, "content", plain_text!(content(block)))}

        _ ->
          {Map.fetch!(@names, type), props}
      end

    properties = Map.put(properties, "relaymarkId", block["id"])

    children =
      cond do
        name == "questionBlock" ->
          [label | options] = content(block)
          require!(label["type"] == "paragraph", :question_label)
          label = encode_block(label) |> Map.put("name", "questionLabel")
          [label | Enum.map(options, &encode_block/1)]

        name in @inline_names ->
          encode_inline(content(block))

        name == "agentSuggestion" ->
          []

        true ->
          Enum.map(content(block), &encode_block/1)
      end

    element(name, properties, children)
  end

  defp descendant_blocks(nodes, depth) do
    require!(depth <= 64, :depth_limit)

    Enum.flat_map(nodes, fn node ->
      if node["kind"] == "element" and Map.has_key?(@fields, node["name"]) do
        [node | descendant_blocks(Map.get(node, "children", []) |> list!(), depth + 1)]
      else
        []
      end
    end)
  end

  defp decode_block(node, parent) do
    only!(node, ~w(kind name attributes children))
    require!(node["kind"] == "element", :element_required)
    name = node["name"]
    require!(Map.has_key?(@fields, name), {:unknown_node, name})
    attributes = attrs(node) |> normalize_structural_numbers()
    only!(attributes, ["relaymarkId" | @fields[name]])
    children = Map.fetch!(node, "children") |> list!()
    id = attributes["relaymarkId"]
    props = Map.delete(attributes, "relaymarkId")
    if name in @atom_names, do: require!(children == [], :atom_children)

    if name in @inline_names do
      require!(
        Enum.all?(
          children,
          &(&1["kind"] == "text" or &1["name"] in ~w(hardBreak relayReference relayTag))
        ),
        :inline_children
      )
    end

    {type, props} =
      case name do
        "questionLabel" ->
          require!(parent == "questionBlock", :question_label_parent)
          {"paragraph", %{}}

        "questionOption" ->
          require!(parent == "questionBlock", :option_parent)
          validate_form_props!(props, true)
          {"relay.form_option", props}

        "questionBlock" ->
          validate_form_props!(props, false)

          require!(
            children != [] and hd(children)["name"] == "questionLabel" and
              Enum.all?(tl(children), &(&1["name"] == "questionOption")),
            :question_children
          )

          option_ids = Enum.map(tl(children), &attrs(&1)["id"])

          require!(
            length(option_ids) == length(Enum.uniq(option_ids)),
            :duplicate_option_identity
          )

          {"relay.form_question", props}

        "heading" ->
          require!(is_integer(props["level"]) and props["level"] in 1..6, :heading_level)

          require!(
            is_nil(props["headingId"]) or
              Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/, props["headingId"]),
            :heading_anchor
          )

          {"heading", Map.put_new(props, "headingId", nil)}

        "codeBlock" ->
          require!(
            is_nil(props["language"]) or
              (is_binary(props["language"]) and
                 not String.contains?(props["language"], ["\r", "\n"])),
            :code_language
          )

          require!(
            Enum.all?(children, fn c ->
              c["kind"] == "text" and
                Enum.all?(c["delta"], &(Map.get(&1, "attributes", %{}) == %{}))
            end),
            :code_marks
          )

          {"code", Map.put_new(props, "language", nil)}

        "bulletList" ->
          require!(
            children != [] and Enum.all?(children, &(&1["name"] == "listItem")),
            :list_children
          )

          {"list", %{"kind" => "bullet"}}

        "orderedList" ->
          require!(is_nil(props["type"]), :ordered_type)
          require!(is_integer(props["start"]) and props["start"] > 0, :ordered_start)

          require!(
            children != [] and Enum.all?(children, &(&1["name"] == "listItem")),
            :list_children
          )

          {"list", %{"kind" => "ordered", "start" => props["start"]}}

        "listItem" ->
          require!(parent in ~w(bulletList orderedList), :list_item_parent)
          require!(children != [] and hd(children)["name"] == "paragraph", :list_first_paragraph)
          {"list_item", %{}}

        "taskList" ->
          require!(
            children != [] and Enum.all?(children, &(&1["name"] == "taskItem")),
            :task_children
          )

          {"task_list", %{}}

        "taskItem" ->
          props = Map.put_new(props, "checked", false)

          require!(
            parent == "taskList" and children != [] and hd(children)["name"] == "paragraph",
            :task_parent
          )

          require!(
            is_boolean(props["checked"]) and
              (is_nil(props["entityId"]) or uuid?(props["entityId"])),
            :task_props
          )

          {"task_item", Map.put_new(props, "entityId", nil)}

        "blockquote" ->
          require!(children != [], :quote_children)
          {"quote", %{}}

        "callout" ->
          require!(
            props["tone"] in ~w(neutral primary secondary accent info success warning error) and
              props["emphasis"] in ~w(soft strong),
            :callout_appearance
          )

          names = Enum.map(children, & &1["name"])

          require!(
            names != [] and Enum.count(names, &(&1 == "calloutTitle")) <= 1 and
              ("calloutTitle" not in names or hd(names) == "calloutTitle") and
              names != ["calloutTitle"],
            :callout_children
          )

          {"relay.callout", props}

        "calloutTitle" ->
          require!(parent == "callout", :title_parent)
          {"relay.callout_title", %{}}

        "table" ->
          require!(
            children != [] and Enum.all?(children, &(&1["name"] == "tableRow")),
            :table_children
          )

          validate_table!(children)
          {"table", %{}}

        "tableRow" ->
          require!(
            parent == "table" and Enum.all?(children, &(&1["name"] in ~w(tableCell tableHeader))),
            :row_parent
          )

          {"table_row", %{}}

        name when name in ~w(tableCell tableHeader) ->
          require!(parent == "tableRow" and children != [], :cell_parent)

          require!(
            is_integer(props["colspan"]) and props["colspan"] > 0 and is_integer(props["rowspan"]) and
              props["rowspan"] > 0,
            :cell_spans
          )

          require!(
            is_nil(props["colwidth"]) or
              (is_list(props["colwidth"]) and length(props["colwidth"]) == props["colspan"] and
                 Enum.all?(props["colwidth"], &(is_integer(&1) and &1 >= 0))),
            :cell_width
          )

          require!(props["align"] in [nil, "left", "center", "right"], :cell_alignment)

          {"table_cell",
           props
           |> Map.put("header", name == "tableHeader")
           |> Map.put_new("align", nil)
           |> Map.put_new("colwidth", nil)}

        "image" ->
          require!(safe_image?(props["src"]), :image_source)

          Enum.each(~w(alt title), fn key ->
            require!(
              is_nil(props[key]) or
                (is_binary(props[key]) and not String.contains?(props[key], ["\r", "\n"])),
              :image_text
            )
          end)

          Enum.each(~w(width height), fn key ->
            require!(
              is_nil(props[key]) or (is_integer(props[key]) and props[key] > 0),
              :image_dimensions
            )
          end)

          {"image",
           props
           |> Map.put_new("alt", nil)
           |> Map.put_new("title", nil)
           |> Enum.reject(fn {k, v} -> k in ~w(width height) and is_nil(v) end)
           |> Map.new()}

        "videoEmbed" ->
          require!(uuid?(props["videoId"]), :video_identity)

          require!(
            props["source"] in [nil, "mux"] and props["status"] in [nil, "ready"],
            :video_transient_state
          )

          require!(
            Enum.all?(
              ~w(playbackId title thumbnailUrl youtubeId uploadPercent),
              &is_nil(props[&1])
            ),
            :video_hydration
          )

          {"relay.video_embed", Map.take(props, ~w(videoId))}

        "relayEntityReference" ->
          {:ok, fields} = RelayMark.EntityReference.parse_source(props["source"])

          require!(
            props["entityType"] == "Entity" and props["entityId"] == fields["entityId"] and
              props["entityRef"] == fields["id"] and props["label"] == fields["label"] and
              props["projection"] == fields["projection"],
            :reference_identity
          )

          {"relay.entity_reference", Map.take(fields, ~w(id label projection source))}

        name when name in ~w(relayButton relayAnchor relayConnection) ->
          control =
            %{
              "relayButton" => "button",
              "relayAnchor" => "anchor",
              "relayConnection" => "connection"
            }[name]

          authored = Map.put(props, "control", control)
          {:ok, source} = RelayMark.PaperControl.canonical_source(authored)
          {"relay.paper_control", Map.put(authored, "source", source)}

        "agentSuggestion" ->
          authored = Map.put(props, "relaymarkId", id)

          require!(
            match?({:ok, _}, RelayMark.AgentSuggestion.to_block(authored)),
            :suggestion_props
          )

          {"relay.agent_suggestion", Map.delete(props, "content")}

        "relayDataView" ->
          validate_data_view!(props)
          {"relay.data_view", props |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()}

        _ ->
          case RelayMark.DocumentDirectives.type(name) do
            nil ->
              {Enum.find_value(@names, fn {type, n} -> if n == name, do: type end), %{}}

            type ->
              spec = RelayMark.DocumentDirectives.spec(type)

              props =
                Enum.reduce(spec["attributes"], %{}, fn {key, field}, acc ->
                  value = props[key]

                  cond do
                    not is_nil(value) -> Map.put(acc, key, value)
                    Map.has_key?(field, "default") -> Map.put(acc, key, field["default"])
                    field["required"] -> require!(false, :directive_required_field)
                    true -> acc
                  end
                end)

              require!(length(children) >= spec["children"]["min"], :directive_children)
              {type, props}
          end
      end

    content =
      cond do
        name in @inline_names ->
          decode_inline(children)

        name == "agentSuggestion" ->
          [%{"type" => "text", "text" => props_from_node(node)["content"]}]

        true ->
          Enum.map(children, &decode_block(&1, name))
      end

    if spec = RelayMark.DocumentDirectives.spec(type) do
      allowed = spec["children"]["allowed_types"]
      require!(Enum.all?(content, &(&1["type"] in allowed)), :directive_child_type)
    end

    node = %{"id" => id, "type" => type, "content" => content}
    if props == %{}, do: node, else: Map.put(node, "props", props)
  end

  defp validate_data_view!(props) do
    require!(
      is_binary(props["source"]) and
        Regex.match?(~r/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/, props["source"]),
      :data_view_source
    )

    require!(
      props["projection"] in ~w(list table feed calendar kanban chart),
      :data_view_projection
    )

    Enum.each(~w(columns sort), fn key ->
      require!(
        is_nil(props[key]) or (is_list(props[key]) and Enum.all?(props[key], &is_binary/1)),
        :data_view_keys
      )
    end)

    if props["filter"] do
      require!(is_map(props["filter"]), :data_view_filter)

      Enum.each(props["filter"], fn {key, value} ->
        require!(Regex.match?(~r/^[a-z][a-z0-9_]*$/, key), :data_view_filter_key)

        require!(
          filter_scalar?(value) or (is_list(value) and Enum.all?(value, &filter_scalar?/1)),
          :data_view_filter_value
        )
      end)
    end

    require!(
      is_nil(props["group"]) or
        (is_binary(props["group"]) and Regex.match?(~r/^[a-z][a-z0-9_]*$/, props["group"])),
      :data_view_group
    )

    require!(
      is_nil(props["limit"]) or (is_integer(props["limit"]) and props["limit"] in 1..1000),
      :data_view_limit
    )

    require!(is_nil(props["title"]) or is_binary(props["title"]), :data_view_title)
  end

  defp filter_scalar?(value),
    do: is_nil(value) or is_binary(value) or is_boolean(value) or is_number(value)

  defp normalize_structural_numbers(attributes) do
    fields = ~w(level start colspan rowspan width height limit points min max)

    Enum.reduce(fields, attributes, fn key, attrs ->
      if is_number(attrs[key]),
        do: require!(abs(attrs[key]) <= 9_007_199_254_740_991, :numeric_range)

      case attrs[key] do
        value
        when is_float(value) and abs(value) <= 9_007_199_254_740_991 and value == trunc(value) ->
          Map.put(attrs, key, trunc(value))

        _ ->
          attrs
      end
    end)
    |> Map.update("colwidth", nil, fn values ->
      if is_list(values),
        do:
          Enum.map(values, fn
            value
            when is_float(value) and abs(value) <= 9_007_199_254_740_991 and value == trunc(value) ->
              trunc(value)

            value ->
              value
          end),
        else: values
    end)
    |> then(fn attrs ->
      if Map.has_key?(attributes, "colwidth"), do: attrs, else: Map.delete(attrs, "colwidth")
    end)
  end

  defp props_from_node(node), do: Map.delete(attrs(node), "relaymarkId")

  defp validate_form_props!(props, option) do
    require!(is_binary(props["id"]) and String.trim(props["id"]) != "", :form_identity)

    require!(
      if(option,
        do: is_boolean(props["correct"]),
        else: props["type"] in @question_types and is_boolean(props["required"])
      ),
      :form_type
    )

    Enum.each(if(option, do: ~w(points), else: ~w(points min max)), fn key ->
      require!(is_nil(props[key]) or is_number(props[key]), :form_number)
    end)

    require!(is_map(props["settings"]), :form_settings)
    validate_json!(props["settings"], 0)
  end

  defp validate_question_ids!(blocks) do
    questions =
      all_ast_blocks(blocks)
      |> Enum.filter(&(&1["type"] == "relay.form_question"))
      |> Enum.map(& &1["props"]["id"])

    require!(length(questions) == length(Enum.uniq(questions)), :duplicate_question_identity)
  end

  defp all_ast_blocks(blocks),
    do:
      Enum.flat_map(blocks, fn b ->
        [b | all_ast_blocks(Enum.filter(Map.get(b, "content", []), &Map.has_key?(&1, "id")))]
      end)

  defp encode_inline(nodes) do
    Enum.reduce(nodes, [], fn node, acc ->
      child = encode_inline_node(node, %{})

      case {List.last(acc), child} do
        {%{"kind" => "text", "delta" => delta}, %{"kind" => "text", "delta" => next}} ->
          List.replace_at(acc, -1, %{"kind" => "text", "delta" => delta ++ next})

        _ ->
          acc ++ [child]
      end
    end)
  end

  defp encode_inline_node(%{"type" => "text", "text" => text} = node, marks) do
    only!(node, ~w(type text))
    require!(is_binary(text) and text != "", :text)

    run =
      if marks == %{}, do: %{"insert" => text}, else: %{"insert" => text, "attributes" => marks}

    %{"kind" => "text", "delta" => [run]}
  end

  defp encode_inline_node(%{"type" => "hard_break"} = node, marks) do
    only!(node, ~w(type))
    require!(marks == %{}, :marked_break)
    element("hardBreak", %{}, [])
  end

  defp encode_inline_node(%{"type" => type} = node, marks)
       when type in ~w(relay.entity_ref relay.tag_ref) do
    require!(marks == %{}, :marked_atom)
    only!(node, ~w(type id label props))
    props = node["props"]

    if type == "relay.entity_ref" do
      only!(props, ~w(entityType source))

      element(
        "relayReference",
        %{
          "entityId" => node["id"],
          "entityType" => props["entityType"],
          "label" => node["label"],
          "source" => props["source"]
        },
        []
      )
    else
      only!(props, ~w(name source))
      require!(node["label"] == "#" <> props["name"], :tag_label)
      element("relayTag", Map.put(props, "id", node["id"]), [])
    end
  end

  defp encode_inline_node(node, marks) do
    {mark, _} =
      Enum.find(@marks, fn {_pm, ast} -> ast == node["type"] end) || require!(false, :inline_type)

    only!(node, if(mark == "link", do: ~w(type href content), else: ~w(type content)))
    require!(length(content(node)) == 1 and not Map.has_key?(marks, mark), :mark_children)
    attrs = if mark == "link", do: Map.put(@link_defaults, "href", node["href"]), else: %{}
    encode_inline_node(hd(content(node)), Map.put(marks, mark, attrs))
  end

  defp decode_inline(nodes), do: Enum.flat_map(nodes, &decode_inline_node/1)

  defp decode_inline_node(%{"kind" => "text", "delta" => delta} = node) do
    only!(node, ~w(kind delta))

    Enum.map(list!(delta), fn run ->
      only!(run, ~w(insert attributes))
      text = run["insert"]
      require!(is_binary(text) and text != "", :text_run)
      marks = Map.get(run, "attributes", %{})
      only!(marks, Enum.map(@marks, &elem(&1, 0)))
      require!(not Map.has_key?(marks, "code") or map_size(marks) == 1, :code_marks)

      Enum.reduce(Enum.reverse(@marks), %{"type" => "text", "text" => text}, fn {pm, ast}, leaf ->
        if Map.has_key?(marks, pm) do
          value = marks[pm]
          require!(is_map(value), :mark_value)

          if pm == "link" do
            only!(value, ~w(href target rel class title))

            require!(
              Map.take(value, Map.keys(@link_defaults)) == @link_defaults,
              :link_attributes
            )

            require!(
              RelayMark.Link.safe_href?(value["href"]),
              :link_href
            )

            %{"type" => ast, "href" => value["href"], "content" => [leaf]}
          else
            require!(value == %{}, :mark_attributes)
            %{"type" => ast, "content" => [leaf]}
          end
        else
          leaf
        end
      end)
    end)
  end

  defp decode_inline_node(node) do
    only!(node, ~w(kind name attributes children))
    require!(node["kind"] == "element" and node["children"] == [], :inline_atom)
    props = attrs(node)

    case node["name"] do
      "hardBreak" ->
        require!(props == %{}, :break_attributes)
        [%{"type" => "hard_break"}]

      "relayReference" ->
        only!(props, ~w(entityType entityId label source status subtitle))
        require!(is_nil(props["status"]) and is_nil(props["subtitle"]), :reference_hydration)
        type = props["entityType"]
        id = props["entityId"]
        label = props["label"]

        require!(
          is_binary(type) and Regex.match?(~r/^[A-Z][A-Za-z0-9]*(?: [A-Z][A-Za-z0-9]*)*$/, type) and
            type != "Tag" and uuid?(id) and is_binary(label) and label != "" and
            String.trim(label) == label and not String.contains?(label, ["\r", "\n", "]"]),
          :inline_reference
        )

        require!(props["source"] == "[[#{type}: #{id} | #{label}]]", :inline_reference_source)

        [
          %{
            "type" => "relay.entity_ref",
            "id" => id,
            "label" => label,
            "props" => Map.take(props, ~w(entityType source))
          }
        ]

      "relayTag" ->
        only!(props, ~w(id name source color))

        require!(
          is_nil(props["color"]) and uuid?(props["id"]) and is_binary(props["name"]) and
            Regex.match?(~r/^[a-z0-9][a-z0-9_-]*$/, props["name"]),
          :inline_tag
        )

        require!(
          props["source"] == "[[Tag: #{props["id"]} | ##{props["name"]}]]",
          :inline_tag_source
        )

        [
          %{
            "type" => "relay.tag_ref",
            "id" => props["id"],
            "label" => "#" <> props["name"],
            "props" => Map.take(props, ~w(name source))
          }
        ]

      _ ->
        require!(false, :unsupported_inline)
    end
  end

  defp plain_text!(nodes),
    do:
      Enum.map_join(nodes, fn node ->
        require!(node["type"] == "text", :suggestion_text)
        node["text"]
      end)

  defp uuid?(id), do: is_binary(id) and Regex.match?(@uuid, id)

  defp safe_image?(src) when is_binary(src) do
    uri = URI.parse(src)

    (Regex.match?(~r|^/m/[A-Za-z0-9_-]{1,128}$|, src) or
       (uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo))) and
      String.trim(src) == src and not Regex.match?(~r/[\x00-\x1f\x7f\\]/, src)
  end

  defp safe_image?(_), do: false

  defp validate_json!(value, depth) do
    require!(depth <= 32, :metadata_depth)

    cond do
      is_map(value) ->
        Enum.each(value, fn {k, v} ->
          require!(is_binary(k), :json_key)
          validate_json!(v, depth + 1)
        end)

      is_list(value) ->
        Enum.each(value, &validate_json!(&1, depth + 1))

      is_nil(value) or is_binary(value) or is_boolean(value) or is_number(value) ->
        :ok

      true ->
        require!(false, :json_value)
    end
  end

  defp validate_table!(rows) do
    require!(length(rows) <= 256, :table_rows)

    {occupied, width} =
      Enum.with_index(rows)
      |> Enum.reduce({MapSet.new(), nil}, fn {row, r}, {occupied, width} ->
        {occupied, _column} =
          Enum.reduce(row["children"], {occupied, 0}, fn cell, {occupied, c} ->
            c = next_column(occupied, r, c)
            props = attrs(cell) |> normalize_structural_numbers()
            colspan = props["colspan"]
            rowspan = props["rowspan"]

            require!(
              is_integer(colspan) and colspan > 0 and is_integer(rowspan) and rowspan > 0 and
                c + colspan <= 256 and r + rowspan <= length(rows),
              :table_spans
            )

            occupied =
              Enum.reduce(r..(r + rowspan - 1), occupied, fn y, acc ->
                Enum.reduce(c..(c + colspan - 1), acc, fn x, set ->
                  require!(not MapSet.member?(set, {y, x}), :table_overlap)
                  MapSet.put(set, {y, x})
                end)
              end)

            {occupied, c + colspan}
          end)

        columns = for {^r, c} <- occupied, do: c
        current = if columns == [], do: 0, else: Enum.max(columns) + 1

        require!(
          current > 0 and (is_nil(width) or width == current) and
            Enum.all?(0..(current - 1), &MapSet.member?(occupied, {r, &1})),
          :table_rectangle
        )

        {occupied, current}
      end)

    require!(MapSet.size(occupied) <= 4096 and is_integer(width), :table_cells)
  end

  defp next_column(occupied, r, c),
    do: if(MapSet.member?(occupied, {r, c}), do: next_column(occupied, r, c + 1), else: c)
end
