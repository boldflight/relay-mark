defmodule RelayMark.DocumentRenderer do
  @moduledoc "Authored static HTML from the strict portable XML contract. Hosts resolve authorized widgets."
  @tags %{
    "paragraph" => "p",
    "blockquote" => "blockquote",
    "bulletList" => "ul",
    "orderedList" => "ol",
    "listItem" => "li",
    "taskList" => "ul",
    "taskItem" => "li",
    "table" => "table",
    "tableRow" => "tr",
    "tableCell" => "td",
    "tableHeader" => "th",
    "calloutTitle" => "div",
    "questionLabel" => "legend",
    "questionOption" => "div"
  }
  @mark_tags [
    {"bold", "strong"},
    {"code", "code"},
    {"italic", "em"},
    {"strike", "s"},
    {"underline", "u"},
    {"highlight", "mark"},
    {"superscript", "sup"},
    {"subscript", "sub"}
  ]
  def render(document) do
    with {:ok, snapshot} <- RelayMark.DocumentXML.from_document(document) do
      {:ok, render_snapshot(snapshot)}
    end
  end

  @doc "Derives readable source and safe HTML from one strictly prepared document."
  def project(document),
    do: RelayMark.DocumentSource.project_with_render(document, &render_snapshot/1)

  defp render_snapshot(snapshot) do
    destinations = heading_destinations(snapshot["children"])
    Enum.map_join(snapshot["children"], &render_node(&1, destinations))
  end

  # Same canonical authored convention as paperDocumentDestinations. XML
  # embeds/hydrated reference labels never contribute to source destination names.
  defp heading_destinations(children) do
    nodes = authored_elements(children)

    used =
      for n <- nodes, n["name"] == "relayAnchor", into: MapSet.new(), do: n["attributes"]["name"]

    {names, _} =
      Enum.reduce(nodes, {%{}, used}, fn n, {names, used} ->
        if n["name"] == "heading" do
          a = n["attributes"]
          base = authored_text(n) |> String.trim() |> String.downcase() |> String.normalize(:nfkd)

          base =
            base
            |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
            |> String.replace(~r/[^a-z0-9_-]+/, "-")
            |> String.trim("-")
            |> String.slice(0, 110)

          identity = a["headingId"] || if(base == "", do: "section", else: base)
          name = unused_destination(identity, used, 1)
          {Map.put(names, a["relaymarkId"], name), MapSet.put(used, name)}
        else
          {names, used}
        end
      end)

    names
  end

  defp authored_elements(children),
    do:
      Enum.flat_map(children, fn
        %{"kind" => "element"} = n -> [n | authored_elements(n["children"] || [])]
        _ -> []
      end)

  defp authored_text(%{"kind" => "text", "delta" => delta}),
    do:
      Enum.map_join(delta, fn run -> if is_binary(run["insert"]), do: run["insert"], else: "" end)

  defp authored_text(n), do: Enum.map_join(n["children"] || [], &authored_text/1)

  defp unused_destination(identity, used, suffix) do
    name = if suffix == 1, do: identity, else: identity <> "-" <> Integer.to_string(suffix)
    if MapSet.member?(used, name), do: unused_destination(identity, used, suffix + 1), else: name
  end

  defp render_node(%{"kind" => "text", "delta" => delta}, _destinations) do
    Enum.map_join(delta, fn run ->
      attrs = run["attributes"] || %{}
      text = escape(run["insert"])

      # Text an agent run wrote (innermost, as the last mark in schema order).
      text =
        if ai = attrs["ai_authored"],
          do: tag("span", [{"data-ai-authored", ""}, {"data-run-id", ai["run_id"]}], text),
          else: text

      text =
        Enum.reduce(Enum.reverse(@mark_tags), text, fn {mark, tag}, html ->
          if Map.has_key?(attrs, mark), do: tag(tag, [], html), else: html
        end)

      if link = attrs["link"],
        do:
          tag(
            "a",
            Enum.map(
              ~w(href target rel class title),
              &{&1, RelayMark.Link.rendered_attributes(link)[&1]}
            ),
            text
          ),
        else: text
    end)
  end

  defp render_node(%{"kind" => "element", "name" => name} = n, destinations) do
    a = n["attributes"] || %{}
    children = Enum.map_join(n["children"] || [], &render_node(&1, destinations))

    if type = RelayMark.DocumentDirectives.type(name) do
      tag(
        "section",
        [
          {"data-relay-directive", type},
          {"data-authored", Jason.encode!(Map.delete(a, "relaymarkId"))}
        ],
        children
      )
    else
      case name do
        "hardBreak" ->
          "<br>"

        "horizontalRule" ->
          "<hr>"

        "heading" ->
          destination = Map.fetch!(destinations, a["relaymarkId"])

          tag(
            "h#{a["level"]}",
            [{"id", destination}, {"data-relay-heading-id", destination}, authored(a)],
            children
          )

        "codeBlock" ->
          tag("pre", [], tag("code", [{"data-language", a["language"]}], children))

        "image" ->
          "<img" <> attributes(Enum.map(~w(src alt title width height), &{&1, a[&1]})) <> ">"

        "table" ->
          # The maintained table convention expands the first row's cell spans.
          # Zero/null widths are unspecified; minimum width belongs to the host.
          cols =
            n["children"]
            |> hd()
            |> Map.fetch!("children")
            |> Enum.map_join(fn cell ->
              attrs = cell["attributes"]

              Enum.map_join(0..(attrs["colspan"] - 1), fn index ->
                width = Enum.at(attrs["colwidth"] || [], index)
                style = if is_integer(width) and width > 0, do: "width: #{width}px"
                "<col" <> attributes([{"style", style}]) <> ">"
              end)
            end)

          tag("table", [], tag("colgroup", [], cols) <> children)

        "callout" ->
          tag(
            "aside",
            [{"data-relay-callout", a["tone"]}, {"data-emphasis", a["emphasis"]}, authored(a)],
            children
          )

        "questionBlock" ->
          tag(
            "fieldset",
            [
              {"data-relay-question", a["id"]},
              {"data-question-type", a["type"]},
              {"data-required", a["required"]}
            ],
            children
          )

        "questionOption" ->
          tag("div", [{"data-relay-option", a["id"]}], children)

        "relayReference" ->
          tag(
            "span",
            [{"data-relay-reference", a["entityId"]}, {"data-source", a["source"]}, authored(a)],
            escape(a["label"])
          )

        "relayTag" ->
          tag(
            "span",
            [{"data-relay-tag", a["id"]}, {"data-source", a["source"]}, authored(a)],
            escape(a["name"])
          )

        "relayEntityReference" ->
          tag(
            "div",
            [
              {"data-relay-reference", a["entityRef"]},
              {"data-projection", a["projection"]},
              {"data-source", a["source"]},
              authored(a)
            ],
            escape(a["label"])
          )

        "videoEmbed" ->
          tag("div", [{"data-relay-video", a["videoId"]}, authored(a)], "")

        "agentSuggestion" ->
          tag(
            "aside",
            [{"data-relay-suggestion", a["review"]}, {"data-kind", a["kind"]}],
            escape(a["content"])
          )

        "relayDataView" ->
          tag(
            "div",
            [
              {"data-relay-data-view", a["source"]},
              {"data-authored", Jason.encode!(Map.delete(a, "relaymarkId"))}
            ],
            escape(a["title"] || a["source"])
          )

        "relayButton" ->
          tag(
            "button",
            [
              {"type", "button"},
              {"disabled", true},
              {"data-relay-kind", a["kind"]},
              {"data-relay-target", a["target"]},
              authored(a)
            ],
            escape(a["label"])
          )

        "relayAnchor" ->
          tag("span", [{"data-relay-anchor", a["name"]}, authored(a)], "")

        "relayConnection" ->
          tag(
            "div",
            [{"data-relay-connection", a["provider"]}, authored(a)],
            escape(a["provider"])
          )

        _ ->
          attrs =
            case name do
              "calloutTitle" ->
                [{"data-callout-title", true}]

              "orderedList" ->
                [{"start", a["start"]}]

              "taskList" ->
                [{"data-relay-task-list", true}]

              "taskItem" ->
                [
                  {"data-checked", a["checked"]},
                  {"data-relay-task-item", a["entityId"]},
                  authored(a)
                ]

              cell when cell in ["tableCell", "tableHeader"] ->
                [
                  {"colspan", a["colspan"]},
                  {"rowspan", a["rowspan"]},
                  {"colwidth", if(a["colwidth"], do: Enum.join(a["colwidth"], ","))},
                  {"data-align", a["align"]},
                  {"style", if(a["align"], do: "text-align: " <> a["align"])}
                ]

              _ ->
                []
            end

          tag(Map.fetch!(@tags, name), attrs, children)
      end
    end
  end

  defp authored(attrs), do: {"data-authored", Jason.encode!(Map.delete(attrs, "relaymarkId"))}

  defp tag(name, attrs, content),
    do: "<" <> name <> attributes(attrs) <> ">" <> content <> "</" <> name <> ">"

  defp attributes(attrs),
    do:
      Enum.map_join(attrs, fn {key, value} ->
        if is_nil(value), do: "", else: " " <> key <> "=\"" <> escape(to_string(value)) <> "\""
      end)

  defp escape(nil), do: ""

  defp escape(text),
    do:
      text
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")
      |> String.replace("\"", "&quot;")
      |> String.replace("'", "&#39;")
end
