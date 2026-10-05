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
      {:ok, Enum.map_join(snapshot["children"], &render_node/1)}
    end
  end

  defp render_node(%{"kind" => "text", "delta" => delta}) do
    Enum.map_join(delta, fn run ->
      attrs = run["attributes"] || %{}
      text = escape(run["insert"])

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

  defp render_node(%{"kind" => "element", "name" => name} = n) do
    a = n["attributes"] || %{}
    children = Enum.map_join(n["children"] || [], &render_node/1)

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
          tag("h#{a["level"]}", [{"id", a["headingId"]}], children)

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
