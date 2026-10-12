defmodule RelayMark.PackagedSpecTest do
  use ExUnit.Case, async: true

  @canonical_root Path.expand("../../../spec/relaymark", __DIR__)
  @packaged_root Path.expand("../priv/relaymark", __DIR__)
  @schema_files ~w(
    contract.json
    editor-schema.json
    xml-attribute-encoding.json
    schemas/relaymark-diagnostic.schema.json
    schemas/relaymark-document.schema.json
    schemas/relaymark-layer-composition.schema.json
    schemas/relaymark-manifest.schema.json
  )

  test "Hex package inputs exactly match the canonical RelayMark spec" do
    relative_paths =
      @schema_files ++
        (@canonical_root
         |> Path.join("directives/*.json")
         |> Path.wildcard()
         |> Enum.map(&Path.relative_to(&1, @canonical_root))
         |> Enum.sort())

    assert packaged_relative_paths() == Enum.sort(relative_paths)

    for relative_path <- relative_paths -- ["contract.json"] do
      assert File.read!(Path.join(@packaged_root, relative_path)) ==
               File.read!(Path.join(@canonical_root, relative_path)),
             "#{relative_path} must be refreshed from the canonical RelayMark spec"
    end
  end

  test "packaged contract includes the canonical physical schema digest" do
    read = fn name ->
      @canonical_root |> Path.join(name) |> File.read!() |> Jason.decode!()
    end

    physical = %{
      "editor_schema" => read.("editor-schema.json"),
      "xml_attribute_encoding" => read.("xml-attribute-encoding.json")
    }

    digest =
      :crypto.hash(:sha256, RelayMark.CanonicalJSON.encode(physical))
      |> Base.encode16(case: :lower)

    expected = Map.put(read.("contract.json"), "schema_hash", digest)
    actual = @packaged_root |> Path.join("contract.json") |> File.read!() |> Jason.decode!()
    assert actual == expected
  end

  test "Hex package ships the canonical pure text-item adapter" do
    canonical = Path.expand("../../collaboration/text-items.js", __DIR__)
    packaged = Path.expand("../priv/collaboration/text-items.js", __DIR__)
    assert File.read!(packaged) == File.read!(canonical)
  end

  test "Hex package ships exact canonical contract and rich adapter modules" do
    for name <-
          ~w(contract.js document-adapter.js document-inline.js document-atoms.js document-reference.js document-controls.js document-suggestion.js) do
      canonical = Path.expand("../../../src/#{name}", __DIR__)
      packaged = Path.expand("../priv/collaboration/#{name}", __DIR__)
      assert File.read!(packaged) == File.read!(canonical)
    end
  end

  defp packaged_relative_paths do
    @packaged_root
    |> Path.join("**/*.json")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, @packaged_root))
    |> Enum.sort()
  end
end
