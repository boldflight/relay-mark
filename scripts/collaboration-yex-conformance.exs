# Optional consumer gate: Yex/Jason must already be compiled on the code path.
# Usage: elixir [consumer -pa paths] scripts/collaboration-yex-conformance.exs NATIVE_JSON OUTPUT_JSON
# Starts no server, Repo, or network provider.
defmodule RelayMarkYexConformance do
  def tree(%Yex.XmlText{} = text) do
    %{
      "kind" => "text",
      "delta" =>
        Enum.map(Yex.XmlText.to_delta(text), fn run ->
          Map.new(run, fn {key, value} -> {to_string(key), value} end)
        end)
    }
  end

  def tree(%Yex.XmlElement{} = element) do
    %{
      "kind" => "element",
      "name" => Yex.XmlElement.get_tag(element),
      "attributes" => Map.new(Yex.XmlElement.get_attributes(element)),
      "children" => Enum.map(Yex.XmlElement.children(element), &tree/1)
    }
  end

  def snapshot(doc) do
    %{
      "kind" => "fragment",
      "children" =>
        doc
        |> Yex.Doc.get_xml_fragment("default")
        |> Yex.XmlFragment.children()
        |> Enum.map(&tree/1)
    }
  end
end

[native_path, output_path] = System.argv()

fixture =
  File.read!(Path.expand("../spec/relaymark/collaboration/fixtures/convergence-v1.json", __DIR__))
  |> Jason.decode!()

native = File.read!(native_path) |> Jason.decode!()

result =
  for item <- fixture["cases"] do
    for order <- item["orders"] do
      doc = Yex.Doc.new()

      for index <- order,
          do: :ok = Yex.apply_update(doc, Base.decode64!(Enum.at(item["updates"], index)))

      if RelayMarkYexConformance.snapshot(doc) != item["expected"],
        do: raise("Yex semantic mismatch: #{item["id"]}")

      {:ok, checkpoint} = Yex.encode_state_as_update(doc)
      restarted = Yex.Doc.new()
      :ok = Yex.apply_update(restarted, checkpoint)

      if RelayMarkYexConformance.snapshot(restarted) != item["expected"],
        do: raise("Yex restart mismatch")
    end

    doc = Yex.Doc.new()
    for update <- item["updates"], do: :ok = Yex.apply_update(doc, Base.decode64!(update))
    update = Enum.find(native["cases"], &(&1["id"] == item["id"]))["update"] |> Base.decode64!()
    :ok = Yex.apply_update(doc, update)
    :ok = Yex.apply_update(doc, update)
    {:ok, checkpoint} = Yex.encode_state_as_update(doc)
    %{"id" => item["id"], "update" => Base.encode64(checkpoint)}
  end

File.write!(output_path, Jason.encode!(%{"cases" => result}))
IO.puts("Yex semantic/reorder/duplicate/checkpoint conformance passed")
