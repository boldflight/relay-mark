# Optional consumer conformance: run with the consumer's already-built MDEx on the code path.
# This script starts no application, server, Repo, or network provider.
Code.require_file("../adapters/elixir/lib/relay_mark/collaborative_prose.ex", __DIR__)

unless Code.ensure_loaded?(MDEx),
  do: raise("Add compiled MDEx dependencies to the Elixir code path")

for text <- ["a`b", "`", "``x`", " padded ", "  ", " left", "right ", "👩🏽‍💻 `é`"] do
  node = %{
    "tag" => "paragraph",
    "attributes" => %{},
    "children" => [
      %{"delta" => [%{"insert" => text, "attributes" => %{"code" => %{}}}]}
    ]
  }

  {:ok, source} = RelayMark.CollaborativeProse.to_markdown([node])

  %{nodes: [%{nodes: [%{__struct__: MDEx.Code, literal: literal}]}]} =
    MDEx.parse_document!(source)

  if literal != text, do: raise("Code span changed: #{inspect({text, source, literal})}")
end

for language <- [nil, "swift", "language`info"],
    text <- ["", "let x = 1", "```\n~~~~\n``````\n", "👩🏽‍💻\n\n"] do
  node = %{
    "tag" => "codeBlock",
    "attributes" => %{"language" => language},
    "children" => [%{"delta" => [%{"insert" => text}]}]
  }

  {:ok, source} = RelayMark.CollaborativeProse.to_markdown([node])

  %{nodes: [%{__struct__: MDEx.CodeBlock, literal: literal, info: info}]} =
    MDEx.parse_document!(source)

  if String.replace_suffix(literal, "\n", "") != text || info != (language || ""),
    do: raise("Code block changed: #{inspect({text, source, literal, info})}")
end

IO.puts("MDEx roundtrip passed: 8 code spans and 12 literal fenced code blocks")
