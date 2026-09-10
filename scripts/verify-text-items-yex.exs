# Trusted synthetic fixtures only. Expected leaf paths assist this interop proof;
# this is NOT an untrusted run decoder or a server authorization/provenance check.
# Run `elixir scripts/verify-text-items-yex.exs`, or `mix run /absolute/path/to/this`
# from a consumer with the exact dependencies below already loaded.
unless Code.ensure_loaded?(Yex.Doc) do
  Mix.install([{:y_ex, "== 0.11.0"}, {:jason, "== 1.4.5"}])
end

for {app, expected} <- [y_ex: "0.11.0", jason: "1.4.5"] do
  unless to_string(Application.spec(app, :vsn)) == expected,
    do: raise("Expected #{app} #{expected}")
end

defmodule RelayMark.TextItemsYexProof do
  def run(path) do
    fixture = Jason.decode!(File.read!(path))

    for scenario <- fixture["cases"] do
      doc = Yex.Doc.with_options(%Yex.Doc.Options{offset_kind: :utf16})
      :ok = Yex.apply_update(doc, Base.decode64!(scenario["update"]))
      expected = scenario["expected"]

      positions =
        for {run, run_index} <- Enum.with_index(scenario["selection"]["runs"]),
            offset <- 0..(run["count"] - 1) do
          item = Map.update!(run["item"], "clock", &(&1 + offset))

          outcomes =
            for assoc <- [0, -1] do
              position = %{"item" => item, "assoc" => assoc}
              {:ok, sticky} = Yex.StickyIndex.from_json(Jason.encode!(position), doc)
              ^position = Jason.decode!(Yex.StickyIndex.to_json(sticky))
              Yex.StickyIndex.get_offset(sticky)
            end

          case outcomes do
            [{:ok, %{index: a}}, {:ok, %{index: b}}] when b == a + 1 ->
              segment = Enum.find(expected["segments"], &(a >= &1["index"] and a < &1["index"] + &1["length"]))
              if is_nil(segment), do: raise("unexpected surviving index")

              leaf =
                Enum.reduce(segment["path"], Yex.Doc.get_xml_fragment(doc, "default"), fn index, parent ->
                  case parent do
                    %Yex.XmlFragment{} -> Yex.XmlFragment.fetch!(parent, index)
                    %Yex.XmlElement{} -> Yex.XmlElement.fetch!(parent, index)
                  end
                end)

              actual = Yex.StickyIndex.new(leaf, a, :after) |> Yex.StickyIndex.to_json() |> Jason.decode!()
              unless actual["item"] == item, do: raise("item or leaf mismatch")
              {:live, a}

            [{:ok, %{index: same}}, {:ok, %{index: same}}] ->
              # get_offset alone cannot verify the historical type of collapsed items.
              :collapsed

            [:error, :error] ->
              {:unavailable, run_index}

            other ->
              raise("unexpected position outcome #{inspect(other)}")
          end
        end

      expected_indices =
        for segment <- expected["segments"],
            index <- segment["index"]..(segment["index"] + segment["length"] - 1), do: index

      actual_indices = for {:live, index} <- positions, do: index
      unless Enum.sort(actual_indices) == Enum.sort(expected_indices), do: raise("surviving mismatch")
      unless Enum.count(positions, &(&1 == :collapsed)) == expected["collapsedUnits"], do: raise("collapsed mismatch")
      unavailable = for {:unavailable, index} <- positions, do: index
      unless Enum.uniq(unavailable) == expected["unavailableRuns"], do: raise("unavailable mismatch")
      IO.puts("PASS #{scenario["name"]}: #{length(positions)} exact item identities")
    end
  end
end

fixture = List.first(System.argv()) || Path.expand("../spec/relaymark/collaboration/fixtures/text-items-v1.json", __DIR__)
RelayMark.TextItemsYexProof.run(fixture)
