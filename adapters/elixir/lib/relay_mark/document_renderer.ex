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
            [
              {"href", link["href"]},
              {"target", "_blank"},
              {"rel", "noopener noreferrer nofollow"}
            ],
            text
          ),
        else: text
    end)
  end

  defp render_node(%{"kind" => "element", "name" => name} = n) do
    a = n["attributes"] || %{}
    children = Enum.map_join(n["children"] || [], &render_node/1)

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

      "callout" ->
        tag(
          "aside",
          [{"data-relay-callout", a["tone"]}, {"data-emphasis", a["emphasis"]}],
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
          [{"data-relay-reference", a["entityId"]}, {"data-source", a["source"]}],
          escape(a["label"])
        )

      "relayTag" ->
        tag(
          "span",
          [{"data-relay-tag", a["id"]}, {"data-source", a["source"]}],
          escape(a["name"])
        )

      "relayEntityReference" ->
        tag(
          "div",
          [
            {"data-relay-reference", a["entityRef"]},
            {"data-projection", a["projection"]},
            {"data-source", a["source"]}
          ],
          escape(a["label"])
        )

      "videoEmbed" ->
        tag("div", [{"data-relay-video", a["videoId"]}], "")

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
            {"data-relay-target", a["target"]}
          ],
          escape(a["label"])
        )

      "relayAnchor" ->
        tag("span", [{"data-relay-anchor", a["name"]}], "")

      "relayConnection" ->
        tag("div", [{"data-relay-connection", a["provider"]}], escape(a["provider"]))

      _ ->
        attrs =
          case name do
            "orderedList" ->
              [{"start", a["start"]}]

            "taskList" ->
              [{"data-relay-task-list", true}]

            "taskItem" ->
              [{"data-checked", a["checked"]}]

            cell when cell in ["tableCell", "tableHeader"] ->
              [{"colspan", a["colspan"]}, {"rowspan", a["rowspan"]}, {"data-align", a["align"]}]

            _ ->
              []
          end

        tag(Map.fetch!(@tags, name), attrs, children)
    end
  end

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
