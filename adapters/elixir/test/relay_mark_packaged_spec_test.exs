defmodule RelayMark.PackagedSpecTest do
  use ExUnit.Case, async: true

  @canonical_root Path.expand("../../../spec/relaymark", __DIR__)
  @packaged_root Path.expand("../priv/relaymark", __DIR__)
  @schema_files ~w(
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

    for relative_path <- relative_paths do
      assert File.read!(Path.join(@packaged_root, relative_path)) ==
               File.read!(Path.join(@canonical_root, relative_path)),
             "#{relative_path} must be refreshed from the canonical RelayMark spec"
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
