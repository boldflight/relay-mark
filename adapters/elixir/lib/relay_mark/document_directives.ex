defmodule RelayMark.DocumentDirectives do
  @moduledoc "Finite editor mappings read from the canonical directive specifications."
  @names %{
    "relay.source_bundle" => "relaySourceBundle",
    "relay.claim" => "relayClaim",
    "relay.evidence_ref" => "relayEvidence",
    "relay.comparison" => "relayComparison",
    "relay.transcript_segment" => "relayTranscript",
    "relay.action_row" => "relayAction",
    "relay.property_sheet" => "relayPropertySheet",
    "relay.layout" => "relayLayout",
    "relay.file_ref" => "relayFile",
    "relay.note_ref" => "relayNote",
    "relay.url_ref" => "relayUrl"
  }
  @paths Path.expand("../../priv/relaymark/directives/*.json", __DIR__) |> Path.wildcard()
  for path <- @paths do
    @external_resource path
  end

  @specs Map.new(@paths, fn path ->
           spec = path |> File.read!() |> Jason.decode!()
           {spec["ast_type"], spec}
         end)
         |> Map.take(Map.keys(@names))
  def names, do: @names
  def spec(type), do: @specs[type]
  def type(name), do: Enum.find_value(@names, fn {type, n} -> if n == name, do: type end)

  def fields,
    do: Map.new(@names, fn {type, name} -> {name, Map.keys(@specs[type]["attributes"])} end)
end
