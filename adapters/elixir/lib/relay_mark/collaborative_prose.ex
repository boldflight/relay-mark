defmodule RelayMark.CollaborativeProse do
  @moduledoc """
  A conservative Markdown projection of the version-one collaborative XML tree.

  Input nodes have `tag`, `attributes`, and `children` string keys; text leaves
  have `delta` entries with `insert` and `attributes`. Unknown nodes, marks and
  attributes fail closed so callers never replace canonical content lossily.
  This codec does not execute embedded tasks or domain actions.
  """

  @spec to_markdown([map()]) :: {:ok, String.t()} | {:error, term()}
  def to_markdown(nodes) when is_list(nodes) do
    {:ok, Enum.map_join(nodes, "\n\n", &block/1)}
  rescue
    _ in [ArgumentError, Protocol.UndefinedError, BadMapError, FunctionClauseError] ->
      {:error, {:unsupported_collaboration_content, :invalid_tree}}
  catch
    {:unsupported, reason} -> {:error, {:unsupported_collaboration_content, reason}}
  end

  defp block(%{"tag" => tag, "attributes" => attrs, "children" => children}) do
    case tag do
      "paragraph" ->
        exact_attrs(attrs, [])
        inline(children)

      "heading" ->
        exact_attrs(attrs, ["level"])
        level = attrs["level"] || 1
        if level not in 1..6, do: unsupported(:heading_level)
        String.duplicate("#", level) <> " " <> inline(children)

      "blockquote" ->
        exact_attrs(attrs, [])

        children
        |> Enum.map_join("\n\n", &block/1)
        |> String.split("\n")
        |> Enum.map_join("\n", &("> " <> &1))

      "bulletList" ->
        exact_attrs(attrs, [])
        list(children, fn _ -> "- " end)

      "orderedList" ->
        exact_attrs(attrs, ["start"])
        start = attrs["start"] || 1
        if not is_integer(start) or start < 1, do: unsupported(:list_start)
        list(children, fn index -> "#{start + index}. " end)

      "codeBlock" ->
        exact_attrs(attrs, ["language"])
        text = plain(children)
        fence = if String.contains?(text, "```"), do: "~~~~", else: "```"
        if String.contains?(text, fence), do: unsupported(:code_fence)
        fence <> (attrs["language"] || "") <> "\n" <> text <> "\n" <> fence

      "horizontalRule" ->
        exact_attrs(attrs, [])
        if children != [], do: unsupported(:rule_children)
        "---"

      _ ->
        unsupported({:node, tag})
    end
  end

  defp block(_), do: unsupported(:block)

  defp list(children, marker) do
    children
    |> Enum.with_index()
    |> Enum.map_join("\n", fn
      {%{"tag" => "listItem", "attributes" => attrs, "children" => items}, index} ->
        exact_attrs(attrs, [])
        prefix = marker.(index)
        [first | rest] = items |> Enum.map_join("\n\n", &block/1) |> String.split("\n")

        prefix <>
          first <>
          Enum.map_join(rest, "", &("\n" <> String.duplicate(" ", String.length(prefix)) <> &1))

      _ ->
        unsupported(:list_item)
    end)
  end

  defp inline(children), do: Enum.map_join(children, "", &inline_node/1)
  defp inline_node(%{"delta" => delta}), do: Enum.map_join(delta, "", &span/1)

  defp inline_node(%{"tag" => "hardBreak", "attributes" => attrs, "children" => []}) do
    exact_attrs(attrs, [])
    "  \n"
  end

  defp inline_node(_), do: unsupported(:inline_node)

  defp span(%{"insert" => text} = item) when is_binary(text) do
    attrs = item["attributes"] || %{}
    exact_attrs(attrs, ["bold", "italic", "strike", "code", "link"])

    value =
      if attrs["code"] do
        if map_size(attrs) > 1 or String.contains?(text, ["`", "\n"]), do: unsupported(:code_span)
        "`" <> text <> "`"
      else
        escape(text)
      end

    value = if attrs["bold"], do: "**" <> value <> "**", else: value
    value = if attrs["italic"], do: "*" <> value <> "*", else: value
    value = if attrs["strike"], do: "~~" <> value <> "~~", else: value

    case attrs["link"] do
      nil ->
        value

      %{"href" => href} = link when is_binary(href) ->
        exact_attrs(link, ["href", "target", "rel", "class"])
        if String.contains?(href, ["\n", "<", ">"]), do: unsupported(:link_destination)
        "[" <> value <> "](<" <> href <> ">)"

      _ ->
        unsupported(:link)
    end
  end

  defp span(_), do: unsupported(:text_embed)

  defp plain(children) do
    Enum.map_join(children, "", fn
      %{"delta" => delta} ->
        Enum.map_join(delta, "", fn
          %{"insert" => text} = item when is_binary(text) ->
            if map_size(item["attributes"] || %{}) != 0, do: unsupported(:code_marks)
            text

          _ ->
            unsupported(:code_content)
        end)

      _ ->
        unsupported(:code_content)
    end)
  end

  defp escape(text), do: String.replace(text, ~r/([\\`*_{}\[\]<>#!+\-.|~])/, "\\\\\\1")

  defp exact_attrs(attrs, keys) do
    if Enum.any?(attrs, fn {key, value} -> key not in keys and not is_nil(value) end),
      do: unsupported(:attributes)
  end

  defp unsupported(reason), do: throw({:unsupported, reason})
end
