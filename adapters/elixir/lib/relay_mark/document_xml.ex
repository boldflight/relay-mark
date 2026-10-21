defmodule RelayMark.DocumentXML do
  @moduledoc """
  The portable XML snapshot of the collaborative fragment: the lossless JSON
  tree of the `Y.XmlFragment` that native and web replicas exchange.
  Conversions run in the canonical RelayMark engine.
  """

  alias RelayMark.Engine

  @code "relaymark.document_xml.invalid"

  @doc "Canonical XML snapshot of a document."
  def from_document(document),
    do: Engine.json("to_snapshot", document) |> RelayMark.keyed_error(@code)

  @doc "Normalize semantic text segmentation, preserving identities and metadata."
  def normalize_document(document),
    do: Engine.json("normalize", document) |> RelayMark.keyed_error(@code)

  @doc "Document of a canonical XML snapshot."
  def to_document(snapshot) when is_map(snapshot),
    do: Engine.json("from_snapshot", snapshot) |> RelayMark.keyed_error(@code)

  def to_document(_), do: RelayMark.keyed_error({:error, "invalid_snapshot"}, @code)

  @doc "Finite original snapshot conversion; canonical geometry is retained without a physical cut. No live admission or undo-history authority."
  def import_aggregate_settings_snapshot(snapshot),
    do: Engine.json("aggregate_settings", snapshot) |> RelayMark.keyed_error(@code)

  @doc "Finite historical XML import with the identity changes for the existing CRDT owner."
  def import_snapshot(snapshot, options \\ []) do
    case Keyword.get(options, :namespace) do
      namespace when is_binary(namespace) and namespace != "" ->
        Engine.json("import_snapshot", snapshot, %{"namespace" => namespace})
        |> RelayMark.keyed_error(@code)

      _ ->
        RelayMark.keyed_error({:error, "import_namespace"}, @code)
    end
  end

  @doc "Validates typing attributes through the canonical rich text/mark owner."
  def validate_text_attributes(attributes) do
    case Engine.json("text_attributes", attributes) |> RelayMark.keyed_error(@code) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc "Finite admitted AST kinds for content-free inventory, from the canonical projection grammar."
  def inventory_types do
    %{
      nodes:
        ~w(ai_authored code code_span emphasis hard_break heading highlight horizontal_rule image link list list_item paragraph quote relay.action_row relay.agent_suggestion relay.callout relay.callout_title relay.claim relay.comparison relay.data_view relay.entity_ref relay.entity_reference relay.evidence_ref relay.file_ref relay.form_option relay.form_question relay.layout relay.note_ref relay.paper_control relay.property_sheet relay.source_bundle relay.tag_ref relay.transcript_segment relay.url_ref relay.video_embed strikethrough strong subscript superscript table table_cell table_row task_item task_list text underline),
      marks:
        ~w(ai_authored code_span emphasis highlight link strikethrough strong subscript superscript underline),
      question_types:
        ~w(calculated_field checkboxes date dropdown email entity_ref file file_upload hidden_field lightning_payment linear_scale long_text multi_select multiple_choice number page_break payment payment_block phone short_text single_select slot_picker video_question video_response)
    }
  end

  @schema_path Path.expand("../../priv/relaymark/editor-schema.json", __DIR__)
  @external_resource @schema_path
  @identified @schema_path
              |> File.read!()
              |> Jason.decode!()
              |> Map.fetch!("nodes")
              |> Enum.filter(&Map.has_key?(&1["attrs"] || %{}, "relaymarkId"))
              |> Enum.map(& &1["name"])
              |> Enum.sort()

  @doc "Canonical element names with authored block identity (not inline entity IDs)."
  def identified_node_names, do: @identified
end
