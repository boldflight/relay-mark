defmodule RelayMark.DocumentSource do
  @moduledoc """
  One canonical source importer. CommonMark and authored directives become the
  strict rich AST; `relaymark-ast` fences are the exact identity/metadata-bearing
  interchange syntax. Readable Markdown is a derived projection, never a second
  writable body. A retry uses the same import namespace or retained parsed AST.
  """
  @options [
    extension: [
      table: true,
      tasklist: true,
      strikethrough: true,
      wikilinks_title_after_pipe: true
    ]
  ]
  @marks ~w(link strong code_span emphasis strikethrough underline highlight superscript subscript)
  @directives Path.expand("../../priv/relaymark/directives", __DIR__)
  def parse(source, options \\ [])

  def parse(source, options) when is_binary(source) do
    attempt(fn ->
      source = String.replace(source, ~r/\r\n?/, "\n")

      ast =
        case Regex.run(~r/\A(`{3,})relaymark-ast\n([\s\S]*?)\n\1\s*\z/, source) do
          [_, _, json] ->
            Jason.decode!(json)

          nil ->
            namespace = Keyword.get(options, :namespace, source)
            unless is_binary(namespace), do: fail(:import_namespace)
            {frontmatter, body} = frontmatter(source)
            blocks = source_blocks(body, namespace, [])

            blocks =
              if blocks == [], do: [block(namespace, [0], "paragraph", [], nil)], else: blocks

            ast = %{"type" => "relaymark.document", "blocks" => blocks}
            if frontmatter == %{}, do: ast, else: Map.put(ast, "frontmatter", frontmatter)
        end

      ensure!(ast)
      ast
    end)
  end

  def parse(_, _),
    do: {:error, [%{level: "critical", code: "relaymark.source.invalid", reason: "input"}]}

  def serialize(ast) do
    attempt(fn ->
      ensure!(ast)
      json = Jason.encode!(ast)
      fence = String.duplicate("`", max(3, longest_ticks(json) + 1))
      fence <> "relaymark-ast\n" <> json <> "\n" <> fence <> "\n"
    end)
  end

  def project_markdown(ast) do
    attempt(fn ->
      ensure!(ast)
      Enum.map_join(ast["blocks"], "\n\n", &markdown/1) <> "\n"
    end)
  end

  defp ensure!(ast) do
    case RelayMark.DocumentXML.from_document(ast) do
      {:ok, _} -> :ok
      {:error, diagnostics} -> throw({:source_diagnostics, diagnostics})
    end
  end

  defp attempt(fun) do
    try do
      {:ok, fun.()}
    rescue
      _ in [ArgumentError, KeyError, MatchError, Jason.DecodeError, FunctionClauseError] ->
        {:error,
         [%{level: "critical", code: "relaymark.source.invalid", reason: "authored_source"}]}
    catch
      {:source_diagnostics, diagnostics} ->
        {:error, diagnostics}

      {:source_error, reason} ->
        {:error,
         [%{level: "critical", code: "relaymark.source.invalid", reason: Atom.to_string(reason)}]}
    end
  end

  defp fail(reason), do: throw({:source_error, reason})

  defp longest_ticks(s),
    do: Regex.scan(~r/`+/, s) |> Enum.map(fn [x] -> String.length(x) end) |> Enum.max(fn -> 0 end)

  defp frontmatter("---\n" <> rest) do
    case String.split(rest, "\n---", parts: 2) do
      [header, body] ->
        attrs =
          header
          |> String.split("\n", trim: true)
          |> Map.new(fn line ->
            case String.split(line, ":", parts: 2) do
              [key, value] -> {String.trim(key), frontmatter_value(String.trim(value))}
              _ -> fail(:frontmatter)
            end
          end)

        {attrs, String.trim_leading(body, "\n")}

      _ ->
        fail(:frontmatter)
    end
  end

  defp frontmatter(body), do: {%{}, body}

  defp frontmatter_value(value) do
    case Jason.decode(value) do
      {:ok, v} -> v
      _ -> value
    end
  end

  # Scan only block directive headers. Fences are opaque to the scanner, so code
  # examples containing @Callout or closing braces never change the grammar.
  defp source_blocks(source, namespace, prefix) do
    {segments, plain, unfinished, _} =
      source
      |> String.split("\n")
      |> Enum.reduce({[], [], nil, nil}, fn line, {segments, plain, directive, fence} ->
        trimmed = String.trim(line)

        cond do
          fence != nil ->
            closing =
              Regex.match?(~r/^(`{3,}|~{3,})\s*$/, trimmed) and
                String.starts_with?(trimmed, String.slice(fence, 0, 1)) and
                String.length(trimmed) >= String.length(fence)

            append_source_line(
              segments,
              plain,
              directive,
              line,
              if(closing, do: nil, else: fence)
            )

          Regex.match?(~r/^(`{3,}|~{3,})/, trimmed) ->
            [marker] = Regex.run(~r/^(`{3,}|~{3,})/, trimmed, capture: :all_but_first)
            append_source_line(segments, plain, directive, line, marker)

          directive != nil ->
            {header, body, depth} = directive

            cond do
              String.starts_with?(header, "<!--") and
                  Regex.match?(~r/^<!--\s*\/relay:question\s*-->$/, trimmed) ->
                {segments ++ [{:historical_question, header, Enum.join(body, "\n")}], [], nil,
                 nil}

              String.starts_with?(header, "<!--") ->
                {segments, plain, {header, body ++ [line], depth}, nil}

              trimmed == "}" and depth == 1 ->
                {segments ++ [{:directive, header, Enum.join(body, "\n")}], [], nil, nil}

              trimmed == "}" ->
                {segments, plain, {header, body ++ [line], depth - 1}, nil}

              Regex.match?(~r/^@[A-Z][A-Za-z0-9]*(?:\(.*\))?\s*\{\s*$/, trimmed) ->
                {segments, plain, {header, body ++ [line], depth + 1}, nil}

              true ->
                {segments, plain, {header, body ++ [line], depth}, nil}
            end

          Regex.match?(~r/^<!--\s*relay:question\s+.*?\s*-->$/, trimmed) ->
            {flush(segments, plain), [], {trimmed, [], 1}, nil}

          Regex.match?(~r/^<!--\s*\/relay:question\s*-->$/, trimmed) ->
            fail(:unexpected_question_closing)

          Regex.match?(~r/^@[A-Z][A-Za-z0-9]*(?:\(.*\))?\s*\{\s*$/, trimmed) ->
            {flush(segments, plain), [], {trimmed, [], 1}, nil}

          Regex.match?(~r/^@(Button|Anchor|Connection)\(/, trimmed) ->
            {flush(segments, plain) ++ [{:control, trimmed}], [], nil, nil}

          trimmed == "}" ->
            fail(:unexpected_closing)

          true ->
            {segments, plain ++ [bare_linked_task_line(line)], nil, nil}
        end
      end)

    if unfinished != nil, do: fail(:missing_closing)

    segments = flush(segments, plain)

    segments
    |> Enum.with_index()
    |> Enum.flat_map(fn {segment, index} ->
      path = prefix ++ [index]

      case segment do
        {:markdown, body} ->
          MDEx.parse_document!(body, @options).nodes
          |> Enum.with_index()
          |> Enum.map(fn {node, i} -> convert(node, namespace, path ++ [i]) end)

        {:historical_question, header, body} ->
          [historical_question(header, body, namespace, path)]

        {:directive, header, body} ->
          [directive(header, body, namespace, path)]

        {:control, source} ->
          [control(source, namespace, path)]
      end
    end)
  end

  defp append_source_line(segments, plain, nil, line, fence),
    do: {segments, plain ++ [line], nil, fence}

  defp append_source_line(segments, plain, {header, body, depth}, line, fence),
    do: {segments, plain, {header, body ++ [line], depth}, fence}

  defp flush(segments, []), do: segments
  defp flush(segments, lines), do: segments ++ [{:markdown, Enum.join(lines, "\n")}]

  defp block(ns, path, type, content, props) do
    value = %{"id" => id(ns, path), "type" => type, "content" => content}
    if props in [nil, %{}], do: value, else: Map.put(value, "props", props)
  end

  defp id(ns, path) do
    <<a::binary-size(12), _::binary-size(1), b::binary-size(3), _::binary-size(1),
      c::binary-size(15), _::binary>> =
      :crypto.hash(:sha256, ns <> "\0" <> Enum.join(path, ".")) |> Base.encode16(case: :lower)

    "b" <> a <> "4" <> b <> "8" <> c
  end

  defp convert(%MDEx.Paragraph{nodes: [%MDEx.Image{} = image]}, ns, path),
    do: image(image, ns, path)

  defp convert(%MDEx.Paragraph{} = n, ns, path),
    do: block(ns, path, "paragraph", inline(n.nodes), nil) |> historical_media()

  defp convert(%MDEx.HtmlBlock{literal: text}, ns, path),
    do: block(ns, path, "paragraph", [%{"type" => "text", "text" => text}], nil)

  defp convert(%MDEx.Heading{} = n, ns, path),
    do: block(ns, path, "heading", inline(n.nodes), %{"level" => n.level, "headingId" => nil})

  defp convert(%MDEx.BlockQuote{} = n, ns, path),
    do: block(ns, path, "quote", convert_children(n.nodes, ns, path), nil)

  defp convert(%MDEx.List{} = n, ns, path) do
    task = n.is_task_list

    children =
      Enum.with_index(n.nodes)
      |> Enum.map(fn {item, i} ->
        content = convert_children(item.nodes, ns, path ++ [i])

        if task do
          {content, entity_id} = linked_task(content)

          block(ns, path ++ [i], "task_item", content, %{
            "checked" => Map.get(item, :checked, false),
            "entityId" => entity_id
          })
        else
          block(ns, path ++ [i], "list_item", content, nil)
        end
      end)

    props =
      if n.list_type == :ordered,
        do: %{"kind" => "ordered", "start" => n.start},
        else: %{"kind" => "bullet"}

    block(
      ns,
      path,
      if(task, do: "task_list", else: "list"),
      children,
      if(task, do: nil, else: props)
    )
  end

  defp convert(%MDEx.CodeBlock{} = n, ns, path) do
    if String.starts_with?(n.info, "relaymark-ast"), do: fail(:mixed_exact_interchange)

    block(
      ns,
      path,
      "code",
      if(n.literal == "", do: [], else: [%{"type" => "text", "text" => n.literal}]),
      %{"language" => if(n.info == "", do: nil, else: n.info)}
    )
  end

  defp convert(%MDEx.ThematicBreak{}, ns, path), do: block(ns, path, "horizontal_rule", [], nil)

  defp convert(%MDEx.Table{} = n, ns, path) do
    rows =
      n.nodes
      |> Enum.with_index()
      |> Enum.map(fn {row, r} ->
        cells =
          row.nodes
          |> Enum.with_index()
          |> Enum.map(fn {cell, c} ->
            alignment = Enum.at(n.alignments, c)
            para = block(ns, path ++ [r, c, 0], "paragraph", inline(cell.nodes), nil)

            block(ns, path ++ [r, c], "table_cell", [para], %{
              "header" => row.header,
              "colspan" => 1,
              "rowspan" => 1,
              "colwidth" => nil,
              "align" => if(alignment == :none, do: nil, else: to_string(alignment))
            })
          end)

        block(ns, path ++ [r], "table_row", cells, nil)
      end)

    block(ns, path, "table", rows, nil)
  end

  defp convert(_, _, _), do: fail(:unsupported_commonmark_node)

  defp convert_children(nodes, ns, path),
    do: nodes |> Enum.with_index() |> Enum.map(fn {n, i} -> convert(n, ns, path ++ [i]) end)

  defp image(n, ns, path),
    do:
      block(ns, path, "image", [], %{
        "src" => n.url,
        "alt" => Enum.map_join(n.nodes, fn x -> Map.get(x, :literal, "") end),
        "title" => if(n.title == "", do: nil, else: n.title)
      })

  defp historical_media(%{"content" => [leaf]} = n) do
    text =
      case leaf do
        %{"type" => "text", "text" => text} ->
          text

        %{"type" => "link", "href" => url, "content" => [%{"type" => "text", "text" => url}]} ->
          url

        _ ->
          nil
      end

    cond do
      is_binary(text) and
          Regex.match?(
            ~r/\A::video\[\/v\/([0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\]\z/u,
            text
          ) ->
        [_, video_id] = Regex.run(~r/\A::video\[\/v\/([^]]+)\]\z/u, text)

        %{
          "id" => n["id"],
          "type" => "relay.video_embed",
          "props" => %{"videoId" => video_id},
          "content" => []
        }

      is_binary(text) and RelayMark.Link.safe_image_source?(text) and
          Regex.match?(~r/\Ahttps:\/\/[^?#]+\.gif(?:[?#]|$)/iu, text) ->
        %{
          "id" => n["id"],
          "type" => "image",
          "props" => %{"src" => text, "alt" => "", "title" => nil},
          "content" => []
        }

      true ->
        n
    end
  end

  defp historical_media(n), do: n

  defp inline(nodes), do: Enum.flat_map(strip_recovery_nodes(nodes), &inline_node(&1, []))

  defp inline_node(%MDEx.Text{literal: text}, marks),
    do: [wrap(%{"type" => "text", "text" => text}, marks)]

  defp inline_node(%MDEx.WikiLink{url: url, nodes: nodes} = node, []) do
    with [_, type, id] <-
           Regex.run(~r/\A([A-Z][A-Za-z0-9]*(?: [A-Z][A-Za-z0-9]*)*):\s*([^ ]+)\z/u, url) do
      raw = Enum.map_join(nodes, fn %MDEx.Text{literal: literal} -> literal end)

      label =
        cond do
          raw == url -> type
          String.starts_with?(raw, "\"\\u") -> Jason.decode!(raw)
          true -> raw
        end

      if type == "Tag" do
        source = "[[Tag: #{id} | #{label}]]"

        case Regex.run(~r/\A#([a-z0-9][a-z0-9_-]*)\z/u, label) do
          [_, name] ->
            [
              %{
                "type" => "relay.tag_ref",
                "id" => id,
                "label" => label,
                "props" => %{"name" => name, "source" => source}
              }
            ]

          _ ->
            literal_wiki(node)
        end
      else
        case RelayMark.InlineAtoms.reference_source(type, id, label) do
          {:ok, source} ->
            [
              %{
                "type" => "relay.entity_ref",
                "id" => id,
                "label" => label,
                "props" => %{"entityType" => type, "source" => source}
              }
            ]

          :error ->
            literal_wiki(node)
        end
      end
    else
      _ -> literal_wiki(node)
    end
  end

  defp inline_node(%MDEx.HtmlInline{literal: literal}, marks) do
    if recovery_marker?(literal),
      do: [],
      else: [wrap(%{"type" => "text", "text" => literal}, marks)]
  end

  defp inline_node(%MDEx.SoftBreak{}, marks),
    do: [wrap(%{"type" => "text", "text" => "\n"}, marks)]

  defp inline_node(%MDEx.LineBreak{}, []), do: [%{"type" => "hard_break"}]

  defp inline_node(%MDEx.Code{literal: text}, _),
    do: [wrap(%{"type" => "text", "text" => text}, [{"code_span", nil}])]

  defp inline_node(%MDEx.Link{} = n, marks),
    do: Enum.flat_map(n.nodes, &inline_node(&1, [{"link", n.url} | marks]))

  defp inline_node(n, marks) do
    type =
      case n.__struct__ do
        MDEx.Strong -> "strong"
        MDEx.Emph -> "emphasis"
        MDEx.Strikethrough -> "strikethrough"
        _ -> fail(:unsupported_commonmark_inline)
      end

    Enum.flat_map(n.nodes, &inline_node(&1, [{type, nil} | marks]))
  end

  defp wrap(node, marks),
    do:
      marks
      |> Enum.uniq()
      |> Enum.sort_by(fn {m, _} -> Enum.find_index(@marks, &(&1 == m)) end, :desc)
      |> Enum.reduce(node, fn {type, href}, child ->
        if href,
          do: %{"type" => type, "href" => href, "content" => [child]},
          else: %{"type" => type, "content" => [child]}
      end)

  defp bare_linked_task_line(line) do
    if Regex.match?(~r/^ {0,3}\[[ xX]\]\s+.*\[\[Task:/u, line),
      do: Regex.replace(~r/^( {0,3})/u, line, "\\1- ", global: false),
      else: line
  end

  defp recovery_marker?(literal),
    do:
      Regex.match?(
        ~r/\A<!--relay-task-draft:[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}-->\z/u,
        literal
      )

  defp literal_wiki(%MDEx.WikiLink{url: url, nodes: nodes}) do
    label = Enum.map_join(nodes, fn %MDEx.Text{literal: literal} -> literal end)
    body = if label == url, do: url, else: url <> "|" <> label
    [%{"type" => "text", "text" => "[[" <> body <> "]]"}]
  end

  defp strip_recovery_nodes(nodes) do
    Enum.reduce(nodes, [], fn node, acc ->
      if match?(%MDEx.HtmlInline{}, node) and recovery_marker?(node.literal) do
        case Enum.reverse(acc) do
          [%MDEx.Text{literal: literal} = text | rest] ->
            literal = String.replace_suffix(literal, " ", "")
            Enum.reverse(if literal == "", do: rest, else: [%{text | literal: literal} | rest])

          _ ->
            acc
        end
      else
        acc ++ [node]
      end
    end)
  end

  defp linked_task([%{"type" => "paragraph", "content" => parts} = paragraph | rest] = content) do
    case List.last(parts) do
      %{"type" => "relay.entity_ref", "id" => id, "props" => %{"entityType" => "Task"}} ->
        parts = Enum.drop(parts, -1)

        parts =
          case List.last(parts) do
            %{"type" => "text", "text" => text} = node ->
              text = String.replace_suffix(text, " ", "")
              Enum.drop(parts, -1) ++ if(text == "", do: [], else: [%{node | "text" => text}])

            _ ->
              parts
          end

        {[%{paragraph | "content" => parts} | rest], id}

      _ ->
        {content, nil}
    end
  end

  defp linked_task(content), do: {content, nil}

  # Finite prerelease input decoder. It emits only canonical rich nodes; the
  # historical comment syntax is never emitted or admitted as a live editor.
  defp historical_question(header, body, ns, path) do
    [raw] = Regex.run(~r/^<!--\s*relay:question\s+(.*?)\s*-->$/, header, capture: :all_but_first)
    pairs = Regex.scan(~r/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*("(?:\\.|[^"\\])*"|'[^']*')/, raw)

    residue =
      Regex.replace(~r/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*("(?:\\.|[^"\\])*"|'[^']*')/, raw, "")
      |> String.trim()

    if residue != "", do: fail(:historical_question_attributes)

    attrs =
      Map.new(pairs, fn [_, key, value] ->
        {key, decode_entities(String.slice(value, 1, String.length(value) - 2))}
      end)

    if map_size(attrs) != length(pairs), do: fail(:historical_question_attributes)
    type = attrs["type"] || "short_text"

    settings =
      case attrs["settings"] do
        nil ->
          %{}

        text ->
          case Jason.decode(text) do
            {:ok, value} when is_map(value) -> value
            _ -> fail(:historical_question_settings)
          end
      end

    settings =
      Map.drop(attrs, ~w(id type required points min max settings label options))
      |> Enum.reduce(settings, fn {key, text}, acc ->
        if Map.has_key?(acc, key), do: fail(:historical_question_settings)
        Map.put(acc, key, frontmatter_value(text))
      end)

    pattern =
      if type == "checkboxes",
        do: ~r/^\s*-?\s*\[([xX ])\]\s*(.*)$/,
        else: ~r/^\s*-?\s*\(([xX ])\)\s*(.*)$/

    {labels, options} =
      body
      |> String.split("\n")
      |> Enum.reduce({[], []}, fn line, {labels, options} ->
        line = String.trim(line)

        match =
          if type in ~w(multiple_choice dropdown checkboxes),
            do: Regex.run(pattern, line),
            else: nil

        case match do
          [_, marker, text] ->
            {labels,
             options ++
               [%{"text" => String.trim(text), "correct" => String.downcase(marker) == "x"}]}

          _ ->
            if line == "", do: {labels, options}, else: {labels ++ [line], options}
        end
      end)

    explicit =
      case attrs["options"] do
        nil ->
          nil

        text ->
          case Jason.decode(text) do
            {:ok, value} when is_list(value) -> value
            _ -> fail(:historical_question_options)
          end
      end

    if explicit && options != [] && length(explicit) != length(options),
      do: fail(:historical_question_options)

    options =
      if explicit,
        do:
          explicit
          |> Enum.with_index()
          |> Enum.map(fn {option, i} -> Map.merge(Enum.at(options, i, %{}), option) end),
        else: options

    label = Enum.join(labels, "\n")
    label = if label == "", do: attrs["label"] || "", else: label
    label_node = block(ns, path ++ [0], "paragraph", source_inline(label), nil)

    option_nodes =
      options
      |> Enum.with_index(1)
      |> Enum.map(fn {option, index} ->
        text = option["label"] || option["text"] || ""

        slug =
          text
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "-")
          |> String.trim("-")
          |> String.slice(0, 80)

        option_id = option["id"] || if(slug == "", do: "option-#{index}", else: slug)

        props = %{
          "id" => option_id,
          "correct" => Map.get(option, "correct", false),
          "points" => option["points"],
          "settings" => Map.get(option, "settings", %{})
        }

        extras = Map.drop(option, ~w(id label text correct points settings))
        props = Map.update!(props, "settings", &Map.merge(&1, extras))
        block(ns, path ++ [index], "relay.form_option", source_inline(text), props)
      end)

    props = %{
      "id" => attrs["id"],
      "type" => type,
      "required" => attrs["required"] == "true",
      "points" => historical_number(attrs["points"]),
      "min" => historical_number(attrs["min"]),
      "max" => historical_number(attrs["max"]),
      "settings" => settings
    }

    block(ns, path, "relay.form_question", [label_node | option_nodes], props)
  end

  defp historical_number(nil), do: nil

  defp historical_number(text) do
    case Jason.decode(text) do
      {:ok, value} when is_number(value) -> value
      _ -> fail(:historical_question_number)
    end
  end

  defp source_inline(""), do: []

  defp source_inline(text) do
    case MDEx.parse_document!(text, @options).nodes do
      [%MDEx.Paragraph{nodes: nodes}] -> inline(nodes)
      _ -> fail(:question_inline_label)
    end
  end

  defp decode_entities(text),
    do:
      text
      |> String.replace("&quot;", "\"")
      |> String.replace("&#39;", "'")
      |> String.replace("&lt;", "<")
      |> String.replace("&gt;", ">")
      |> String.replace("&amp;", "&")

  defp directive(header, body, ns, path) do
    [_, name, raw] = Regex.run(~r/^@([A-Z][A-Za-z0-9]*)(?:\((.*)\))?\s*\{\s*$/, header)

    spec =
      Path.wildcard(Path.join(@directives, "*.json"))
      |> Enum.map(fn p -> p |> File.read!() |> Jason.decode!() end)
      |> Enum.find(&(&1["name"] == name))

    unless spec, do: fail(:unknown_directive)
    props = attributes(raw || "")

    props =
      Enum.reduce(spec["attributes"] || %{}, props, fn {key, attr}, p ->
        if Map.has_key?(attr, "default"), do: Map.put_new(p, key, attr["default"]), else: p
      end)

    type = spec["ast_type"]
    children = source_blocks(body, ns, path ++ [0])

    {props, children} =
      case type do
        "relay.callout" ->
          {title, props} = Map.pop(props, "title")

          if title,
            do:
              {props,
               [
                 block(
                   ns,
                   path ++ [1],
                   "relay.callout_title",
                   title_inline(title),
                   nil
                 )
                 | children
               ]},
            else: {props, children}

        "relay.form_option" ->
          {props, flatten(children)}

        "relay.agent_suggestion" ->
          {props, flatten(children)}

        "relay.entity_reference" ->
          input =
            if is_binary(props["id"]) and not String.starts_with?(props["id"], "entity:"),
              do: Map.update!(props, "id", &("entity:" <> &1)),
              else: props

          body = if String.starts_with?(body, "  "), do: String.slice(body, 2..-1//1), else: body

          case RelayMark.EntityReference.canonical_source(input, body) do
            {:ok, source} ->
              {:ok, parsed} = RelayMark.EntityReference.parse_source(source)
              {Map.take(parsed, ["id", "label", "projection", "source"]), []}

            _ ->
              fail(:entity_reference_source)
          end

        _ ->
          {props, children}
      end

    block(ns, path, type, children, props)
  end

  # Prefix a plain inline sentinel so the maintained block parser cannot treat
  # an inline title as an HTML block, heading, list, or thematic break.
  defp title_inline(title) do
    case MDEx.parse_document!("\u2060" <> title, @options).nodes do
      [%MDEx.Paragraph{nodes: [%MDEx.Text{literal: "\u2060" <> rest} = first | nodes]}] ->
        inline(if(rest == "", do: nodes, else: [%{first | literal: rest} | nodes]))

      _ ->
        fail(:directive_inline_content)
    end
  end

  defp flatten([%{"type" => "paragraph", "content" => content}]), do: content
  defp flatten([]), do: []
  defp flatten(_), do: fail(:directive_inline_content)

  defp control(source, ns, path) do
    [_, name, raw] = Regex.run(~r/^@(Button|Anchor|Connection)\((.*)\)$/, source)
    control = String.downcase(name)
    props = attributes(raw) |> Map.put("control", control)
    {:ok, canonical} = RelayMark.PaperControl.canonical_source(props)
    block(ns, path, "relay.paper_control", [], Map.put(props, "source", canonical))
  end

  defp attributes(raw) do
    split_top(raw, ?,)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce(%{}, fn pair, attrs ->
      case split_top(pair, ?:) do
        [key, raw_value] ->
          key = key |> String.trim() |> String.trim("\"")
          if Map.has_key?(attrs, key), do: fail(:duplicate_directive_attribute)
          Map.put(attrs, key, value(raw_value))

        _ ->
          fail(:directive_attributes)
      end
    end)
  end

  defp value(raw) do
    raw = String.trim(raw)

    case Jason.decode(raw) do
      {:ok, value} ->
        value

      _ ->
        if String.starts_with?(raw, "{") and String.ends_with?(raw, "}"),
          do: attributes(String.slice(raw, 1, String.length(raw) - 2)),
          else: fail(:directive_attributes)
    end
  end

  defp split_top(raw, delimiter) do
    {parts, current, depth, quote, _} =
      raw
      |> String.to_charlist()
      |> Enum.reduce({[], [], 0, false, false}, fn char, {parts, current, depth, quote, escape} ->
        cond do
          escape ->
            {parts, current ++ [char], depth, quote, false}

          char == ?\\ ->
            {parts, current ++ [char], depth, quote, true}

          char == ?" ->
            {parts, current ++ [char], depth, !quote, false}

          quote ->
            {parts, current ++ [char], depth, quote, false}

          char in [?[, ?{, ?(] ->
            {parts, current ++ [char], depth + 1, quote, false}

          char in [?], ?}, ?)] ->
            {parts, current ++ [char], depth - 1, quote, false}

          char == delimiter and depth == 0 ->
            {parts ++ [current |> to_string() |> String.trim()], [], depth, quote, false}

          true ->
            {parts, current ++ [char], depth, quote, false}
        end
      end)

    if quote or depth != 0, do: fail(:directive_attributes)
    parts ++ [current |> to_string() |> String.trim()]
  end

  defp markdown(%{"type" => "paragraph"} = n), do: markdown_inline(n["content"])

  defp markdown(%{"type" => "heading"} = n),
    do: String.duplicate("#", n["props"]["level"]) <> " " <> markdown_inline(n["content"])

  defp markdown(%{"type" => "quote"} = n),
    do:
      Enum.map_join(n["content"], "\n\n", &markdown/1)
      |> String.split("\n")
      |> Enum.map_join("\n", &("> " <> &1))

  defp markdown(%{"type" => "code"} = n) do
    text = Enum.map_join(n["content"], &(&1["text"] || ""))
    f = String.duplicate("`", max(3, longest_ticks(text) + 1))

    f <>
      (n["props"]["language"] || "") <>
      "\n" <> text <> if(String.ends_with?(text, "\n"), do: "", else: "\n") <> f
  end

  defp markdown(%{"type" => "horizontal_rule"}), do: "---"

  defp markdown(%{"type" => "image"} = n),
    do: "![" <> (n["props"]["alt"] || "") <> "](" <> n["props"]["src"] <> ")"

  defp markdown(%{"type" => type} = n) when type in ["list", "task_list"] do
    n["content"]
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {item, i} ->
      marker =
        cond do
          type == "task_list" -> if(item["props"]["checked"], do: "- [x] ", else: "- [ ] ")
          n["props"]["kind"] == "ordered" -> "#{n["props"]["start"] + i}. "
          true -> "- "
        end

      text = Enum.map_join(item["content"], "\n\n", &markdown/1)
      [first | rest] = String.split(text, "\n")

      marker <>
        first <>
        Enum.map_join(rest, "", &("\n" <> String.duplicate(" ", String.length(marker)) <> &1))
    end)
  end

  defp markdown(%{"type" => "table"} = n) do
    rows =
      Enum.map(n["content"], fn row ->
        "| " <>
          Enum.map_join(row["content"], " | ", fn cell ->
            Enum.map_join(cell["content"], " ", &markdown/1)
            |> String.replace("|", "\\|")
            |> String.replace("\n", "<br>")
          end) <> " |"
      end)

    [head | tail] = rows

    separator =
      "| " <>
        Enum.map_join(hd(n["content"])["content"], " | ", fn c ->
          case c["props"]["align"] do
            "left" -> ":---"
            "center" -> ":---:"
            "right" -> "---:"
            _ -> "---"
          end
        end) <> " |"

    Enum.join([head, separator | tail], "\n")
  end

  defp markdown(%{"type" => "relay.callout_title"} = n), do: markdown_inline(n["content"])
  defp markdown(%{"type" => "relay.form_option"} = n), do: "- " <> markdown_inline(n["content"])
  defp markdown(%{"type" => "relay.paper_control"} = n), do: n["props"]["source"]
  defp markdown(%{"type" => "relay.entity_reference"} = n), do: n["props"]["source"]

  defp markdown(%{"type" => type} = n) do
    label =
      case type do
        "relay.callout" -> "Callout"
        "relay.form_question" -> "Question"
        "relay.agent_suggestion" -> "AgentSuggestion"
        "relay.data_view" -> "DataView"
        "relay.video_embed" -> "Video"
        _ -> fail(:markdown_projection)
      end

    children =
      if type == "relay.agent_suggestion",
        do: markdown_inline(n["content"]),
        else: Enum.map_join(n["content"], "\n\n", &markdown/1)

    "@" <>
      label <>
      "(" <>
      Enum.map_join(n["props"] || %{}, ", ", fn {k, v} -> k <> ": " <> Jason.encode!(v) end) <>
      ") {\n" <> children <> "\n}"
  end

  defp markdown_inline(nodes),
    do:
      Enum.map_join(nodes, fn n ->
        case n["type"] do
          "text" ->
            String.replace(n["text"], ~r/([\\`*_[\]])/, "\\\\\\1")

          "hard_break" ->
            "  \n"

          type when type in ["relay.entity_ref", "relay.tag_ref"] ->
            n["props"]["source"]

          "link" ->
            "[" <> markdown_inline(n["content"]) <> "](" <> n["href"] <> ")"

          "code_span" ->
            text = hd(n["content"])["text"]
            f = String.duplicate("`", longest_ticks(text) + 1)
            f <> text <> f

          type ->
            delimiter =
              case type do
                "strong" -> "**"
                "emphasis" -> "*"
                "strikethrough" -> "~~"
                "underline" -> "<u>"
                "highlight" -> "<mark>"
                "superscript" -> "<sup>"
                "subscript" -> "<sub>"
              end

            finish =
              if String.starts_with?(delimiter, "<"),
                do: String.replace(delimiter, "<", "</"),
                else: delimiter

            delimiter <> markdown_inline(n["content"]) <> finish
        end
      end)
end
