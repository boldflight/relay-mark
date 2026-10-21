# Times one job of the Elixir adapter; the counterpart of `examples/bench.rs`.
# Run from adapters/elixir:
#
#   MIX_ENV=test mix run --no-start ../../crates/relaymark-core/tools/bench.exs <job> <input> <iterations>
[job, input, count] = System.argv()
iterations = String.to_integer(count)
text = File.read!(input)
value = if job in ["parse", "load"], do: nil, else: Jason.decode!(text)

run = fn ->
  {:ok, _} =
    case job do
      "parse" -> RelayMark.parse_document(text, namespace: "bench")
      "load" -> RelayMark.parse_document(text)
      "serialize" -> RelayMark.serialize_document(value)
      "markdown" -> RelayMark.project_document_markdown(value)
      "html" -> RelayMark.render_document(value)
      "to_snapshot" -> RelayMark.DocumentXML.from_document(value)
      "from_snapshot" -> RelayMark.DocumentXML.to_document(value)
    end
end

times =
  for _ <- List.duplicate(nil, iterations) do
    {microseconds, _} = :timer.tc(run)
    microseconds / 1000
  end

first = List.first(times) || 0
median = if times == [], do: 0, else: Enum.at(Enum.sort(times), div(length(times), 2))
IO.puts(Jason.encode!(%{engine: "elixir", job: job, iterations: iterations, first_ms: Float.round(first * 1.0, 3), median_ms: Float.round(median * 1.0, 3)}))
