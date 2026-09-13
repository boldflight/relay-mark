# Run from an independent Mix consumer of the unpacked 0.6.2 Hex tarball.
{:ok, "hello 😀"} =
  RelayMark.CollaborativeProse.to_markdown([
    %{
      "tag" => "paragraph",
      "attributes" => %{},
      "children" => [%{"delta" => [%{"insert" => "hello 😀"}]}]
    }
  ])

{:error, {:unsupported_collaboration_content, _}} =
  RelayMark.CollaborativeProse.to_markdown([
    %{"tag" => "unsupported", "attributes" => %{}, "children" => []}
  ])

{:error, [_ | _]} = RelayMark.validate_document(%{})
true = function_exported?(RelayMark, :project_manifest, 2)
~c"0.6.2" = Application.spec(:relay_mark_elixir, :vsn)

IO.puts(
  "Packaged consumer codec, fail-closed behavior, bundled schema and existing projection API PASS"
)
