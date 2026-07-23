defmodule RelayMark.SemanticValidator do
  @moduledoc false

  alias RelayMark.Diagnostic

  @commonmark_inline_types MapSet.new([
                             "text",
                             "hard_break",
                             "soft_break",
                             "link",
                             "emphasis",
                             "strong",
                             "code_span"
                           ])

  @directive_paths Path.expand("../../../../spec/relaymark/directives/*.json", __DIR__)
                   |> Path.wildcard()
                   |> Enum.sort()

  for directive_path <- @directive_paths do
    @external_resource directive_path
  end

  @directive_registry Map.new(@directive_paths, fn path ->
                        json = File.read!(path)
                        directive = Jason.decode!(json)
                        ordered = Jason.decode!(json, objects: :ordered_objects)

                        attributes =
                          case ordered["attributes"] do
                            %Jason.OrderedObject{values: values} ->
                              Enum.map(values, fn {name, _value} ->
                                {name, directive["attributes"][name]}
                              end)

                            nil ->
                              []
                          end

                        {directive["ast_type"],
                         %{
                           "attributes" => attributes,
                           "policy" => directive["policy"] || %{}
                         }}
                      end)

  @spec validate(map()) :: [Diagnostic.t()]
  def validate(document) when is_map(document) do
    diagnostics =
      []
      |> validate_document_type(document)
      |> validate_document_version(document)

    evidence_targets = collect_evidence_targets(document)

    {diagnostics, _seen_ids} =
      Enum.reduce(document["blocks"] || [], {diagnostics, MapSet.new()}, fn block, state ->
        validate_block(block, state, evidence_targets)
      end)

    validate_document_identities(document, diagnostics)
  end

  defp validate_document_type(diagnostics, %{"type" => "relaymark.document"}), do: diagnostics

  defp validate_document_type(diagnostics, _document) do
    append_error(
      diagnostics,
      "relaymark.document.type",
      "Document type must be relaymark.document."
    )
  end

  defp validate_document_version(diagnostics, %{"version" => version})
       when is_integer(version) and version >= 1,
       do: diagnostics

  defp validate_document_version(diagnostics, _document) do
    append_error(
      diagnostics,
      "relaymark.document.version",
      "Document version must be a positive integer."
    )
  end

  defp validate_block(block, {diagnostics, seen_ids}, evidence_targets) do
    id = block["id"]

    {diagnostics, seen_ids} =
      cond do
        not non_empty_string?(id) ->
          {append_error(diagnostics, "relaymark.block.id", "Every block must have an id."),
           seen_ids}

        MapSet.member?(seen_ids, id) ->
          {append_error(
             diagnostics,
             "relaymark.block.duplicate_id",
             "Duplicate block id '#{id}'."
           ), seen_ids}

        true ->
          {diagnostics, MapSet.put(seen_ids, id)}
      end

    type = block["type"]

    diagnostics =
      if non_empty_string?(type) do
        diagnostics
      else
        append_error(
          diagnostics,
          "relaymark.block.type",
          "Block '#{id || "unknown"}' must have a type."
        )
      end

    diagnostics =
      if is_binary(type) and String.starts_with?(type, "relay.") do
        validate_relay_block(block, diagnostics, evidence_targets)
      else
        diagnostics
      end

    Enum.reduce(block["content"] || [], {diagnostics, seen_ids}, fn child, state ->
      if block_node?(child) do
        validate_block(child, state, evidence_targets)
      else
        state
      end
    end)
  end

  defp validate_relay_block(block, diagnostics, evidence_targets) do
    case @directive_registry[block["type"]] do
      nil ->
        append_error(
          diagnostics,
          "relaymark.directive.unknown_type",
          "Unknown Relay block type '#{block["type"]}'."
        )

      directive ->
        props = block["props"] || %{}

        diagnostics =
          Enum.reduce(directive["attributes"], diagnostics, fn {name, attribute}, acc ->
            case Map.fetch(props, name) do
              :error ->
                if attribute["required"] == true do
                  append_error(
                    acc,
                    "relaymark.attribute.required",
                    "#{block["type"]}.#{name} is required."
                  )
                else
                  acc
                end

              {:ok, value} ->
                validate_attribute(block["type"], name, value, attribute, acc)
            end
          end)

        diagnostics =
          if directive["policy"]["requires_review"] == true and
               not Map.has_key?(props, "review") do
            append_error(
              diagnostics,
              "relaymark.policy.review_required",
              "#{block["type"]} requires a review state."
            )
          else
            diagnostics
          end

        evidence_refs = evidence_refs_for(block)

        diagnostics =
          if directive["policy"]["requires_evidence"] == true and
               not Enum.any?(evidence_refs, &non_empty_string?/1) do
            append_error(
              diagnostics,
              "relaymark.policy.evidence_required",
              "#{block["type"]} requires at least one evidence reference."
            )
          else
            diagnostics
          end

        diagnostics =
          if evidence_refs == [] do
            diagnostics
          else
            validate_evidence_references(
              block,
              evidence_refs,
              evidence_targets,
              diagnostics
            )
          end

        diagnostics =
          case block["type"] do
            "relay.action_row" -> validate_action_proposal(block, diagnostics)
            "relay.source_bundle" -> validate_source_bundle(block, diagnostics)
            "relay.evidence_ref" -> validate_evidence_ref(block, diagnostics)
            "relay.claim" -> validate_claim(block, diagnostics)
            "relay.comparison" -> validate_comparison(block, diagnostics)
            _other -> diagnostics
          end

        diagnostics
    end
  end

  defp validate_action_proposal(block, diagnostics) do
    props = block["props"] || %{}

    lifecycle_fields = [
      "proposal_record_id",
      "proposal_revision",
      "decision_id",
      "execution_id",
      "undo_id"
    ]

    lifecycle_aware =
      props["review"] == "undone" or Map.has_key?(props, "proposal_id") or
        Enum.any?(lifecycle_fields, &Map.has_key?(props, &1))

    cond do
      not lifecycle_aware ->
        diagnostics

      not non_empty_string?(props["proposal_id"]) ->
        append_error(
          diagnostics,
          "relaymark.action.proposal_id",
          "relay.action_row lifecycle fields require a non-empty proposal_id."
        )

      true ->
        diagnostics
        |> validate_proposal_record(props)
        |> validate_proposal_revision(props)
        |> validate_lifecycle_ids(props)
        |> validate_lifecycle_state(props)
    end
  end

  defp validate_proposal_record(diagnostics, props) do
    cond do
      not non_empty_string?(props["proposal_record_id"]) ->
        append_error(
          diagnostics,
          "relaymark.action.proposal_record_id",
          "relay.action_row lifecycle fields require a non-empty proposal_record_id for authorized review and undo."
        )

      props["proposal_record_id"] == props["proposal_id"] ->
        append_error(
          diagnostics,
          "relaymark.action.proposal_identity",
          "relay.action_row.proposal_record_id must be distinct from the generator/client proposal_id."
        )

      true ->
        diagnostics
    end
  end

  defp validate_proposal_revision(diagnostics, props) do
    if is_integer(props["proposal_revision"]) and props["proposal_revision"] >= 1 do
      diagnostics
    else
      append_error(
        diagnostics,
        "relaymark.action.proposal_revision",
        "relay.action_row.proposal_revision must be a positive integer for lifecycle-aware proposals."
      )
    end
  end

  defp validate_lifecycle_ids(diagnostics, props) do
    Enum.reduce(["decision_id", "execution_id", "undo_id"], diagnostics, fn field, acc ->
      if Map.has_key?(props, field) and not non_empty_string?(props[field]) do
        append_error(
          acc,
          "relaymark.action.lifecycle_id",
          "relay.action_row.#{field} must be a non-empty string when present."
        )
      else
        acc
      end
    end)
  end

  defp validate_lifecycle_state(diagnostics, %{"review" => review} = props)
       when review in ["draft", "ready"] do
    if Enum.any?(["decision_id", "execution_id", "undo_id"], &Map.has_key?(props, &1)) do
      append_error(
        diagnostics,
        "relaymark.action.lifecycle_state",
        "relay.action_row in #{review} review must not carry decision, execution, or undo ids."
      )
    else
      diagnostics
    end
  end

  defp validate_lifecycle_state(diagnostics, %{"review" => "accepted"} = props) do
    if not non_empty_string?(props["decision_id"]) or
         not non_empty_string?(props["execution_id"]) or Map.has_key?(props, "undo_id") do
      append_error(
        diagnostics,
        "relaymark.action.lifecycle_state",
        "Accepted relay.action_row proposals require decision_id and execution_id and must not carry undo_id."
      )
    else
      diagnostics
    end
  end

  defp validate_lifecycle_state(diagnostics, %{"review" => "rejected"} = props) do
    if not non_empty_string?(props["decision_id"]) or Map.has_key?(props, "execution_id") or
         Map.has_key?(props, "undo_id") do
      append_error(
        diagnostics,
        "relaymark.action.lifecycle_state",
        "Rejected relay.action_row proposals require decision_id and must not carry execution_id or undo_id."
      )
    else
      diagnostics
    end
  end

  defp validate_lifecycle_state(diagnostics, %{"review" => "undone"} = props) do
    if not non_empty_string?(props["decision_id"]) or
         not non_empty_string?(props["execution_id"]) or
         not non_empty_string?(props["undo_id"]) or props["decision_id"] == props["undo_id"] do
      append_error(
        diagnostics,
        "relaymark.action.lifecycle_state",
        "Undone relay.action_row proposals retain the accept decision_id and execution_id and require a distinct undo_id."
      )
    else
      diagnostics
    end
  end

  defp validate_lifecycle_state(diagnostics, _props), do: diagnostics

  defp validate_source_bundle(block, diagnostics) do
    props = block["props"] || %{}

    diagnostics =
      if non_empty_string?(props["id"]) do
        diagnostics
      else
        append_error(
          diagnostics,
          "relaymark.source_bundle.identity",
          "relay.source_bundle requires a non-empty host id."
        )
      end

    revision = props["revision"]

    if Map.has_key?(props, "revision") and
         (not is_integer(revision) or revision < 0) do
      append_error(
        diagnostics,
        "relaymark.source_bundle.revision",
        "relay.source_bundle.revision must be a non-negative integer."
      )
    else
      diagnostics
    end
  end

  defp validate_evidence_ref(block, diagnostics) do
    props = block["props"] || %{}

    diagnostics =
      if non_empty_string?(props["id"]) and non_empty_string?(props["source"]) do
        diagnostics
      else
        append_error(
          diagnostics,
          "relaymark.evidence.identity",
          "relay.evidence_ref requires non-empty id and source values."
        )
      end

    Enum.reduce(["source_type", "source_revision"], diagnostics, fn field, acc ->
      if Map.has_key?(props, field) and not non_empty_string?(props[field]) do
        append_error(
          acc,
          "relaymark.evidence.source",
          "relay.evidence_ref.#{field} must be a non-empty string when present."
        )
      else
        acc
      end
    end)
  end

  defp validate_claim(block, diagnostics) do
    confidence = get_in(block, ["props", "confidence"])

    if is_number(confidence) and (confidence < 0 or confidence > 1) do
      append_error(
        diagnostics,
        "relaymark.claim.confidence_range",
        "relay.claim.confidence must be between 0.0 and 1.0."
      )
    else
      diagnostics
    end
  end

  defp validate_comparison(block, diagnostics) do
    props = block["props"] || %{}
    subjects = if is_list(props["subjects"]), do: props["subjects"], else: []
    criteria = if is_list(props["criteria"]), do: props["criteria"], else: []
    valid_subjects = Enum.filter(subjects, &non_empty_string?/1)
    valid_criteria = Enum.filter(criteria, &non_empty_string?/1)

    diagnostics =
      if length(valid_subjects) < 2 or
           MapSet.size(MapSet.new(valid_subjects)) != length(valid_subjects) do
        append_error(
          diagnostics,
          "relaymark.comparison.subjects",
          "relay.comparison.subjects must contain at least two distinct, non-empty references."
        )
      else
        diagnostics
      end

    diagnostics =
      if valid_criteria == [] or
           MapSet.size(MapSet.new(valid_criteria)) != length(valid_criteria) do
        append_error(
          diagnostics,
          "relaymark.comparison.criteria",
          "relay.comparison.criteria must contain at least one distinct, non-empty key."
        )
      else
        diagnostics
      end

    preferred = props["preferred"]

    diagnostics =
      if is_binary(preferred) and preferred not in subjects do
        append_error(
          diagnostics,
          "relaymark.comparison.preferred",
          "relay.comparison.preferred must be one of relay.comparison.subjects."
        )
      else
        diagnostics
      end

    values = props["values"]

    if is_map(values) do
      Enum.reduce(Enum.uniq(valid_criteria), diagnostics, fn criterion, acc ->
        criterion_values = values[criterion]

        if is_map(criterion_values) do
          Enum.reduce(Enum.uniq(valid_subjects), acc, fn subject, subject_acc ->
            if Map.has_key?(criterion_values, subject) do
              subject_acc
            else
              append_error(
                subject_acc,
                "relaymark.comparison.values_coverage",
                "relay.comparison.values.#{criterion} must include '#{subject}' with a value or explicit null."
              )
            end
          end)
        else
          append_error(
            acc,
            "relaymark.comparison.values_criterion",
            "relay.comparison.values.#{criterion} must be an object keyed by subject reference."
          )
        end
      end)
    else
      diagnostics
    end
  end

  defp validate_evidence_references(block, evidence_refs, evidence_targets, diagnostics) do
    Enum.reduce(evidence_refs, diagnostics, fn reference, acc ->
      cond do
        not non_empty_string?(reference) ->
          append_error(
            acc,
            "relaymark.evidence.invalid_reference",
            "#{block["type"]} evidence references must be non-empty strings."
          )

        evidence_targets != nil and not MapSet.member?(evidence_targets, reference) ->
          append_error(
            acc,
            "relaymark.evidence.unresolved_reference",
            "#{block["type"]} evidence reference '#{reference}' does not resolve."
          )

        true ->
          acc
      end
    end)
  end

  defp collect_evidence_targets(document) do
    targets =
      Enum.reduce(document["resources"] || [], MapSet.new(), fn resource, acc ->
        maybe_put_identity(acc, resource["id"])
      end)

    visit_blocks(document["blocks"] || [], targets, fn block, acc ->
      acc = maybe_put_identity(acc, block["id"])
      props = block["props"] || %{}

      case block["type"] do
        "relay.source_bundle" ->
          maybe_put_identity(acc, props["id"])

        "relay.evidence_ref" ->
          maybe_put_identity(acc, props["id"])

        "relay.transcript_segment" ->
          maybe_put_identity(acc, props["source"])

        "relay.file_ref" ->
          maybe_put_identity(acc, props["id"])

        "relay.note_ref" ->
          acc
          |> maybe_put_identity(props["document"])
          |> maybe_put_identity(props["block"])

        _other ->
          acc
      end
    end)
  end

  defp validate_document_identities(document, diagnostics) do
    identities = %{
      "evidence" => %{},
      "proposal" => %{},
      "proposal_record" => %{},
      "decision" => %{},
      "execution" => %{},
      "undo" => %{}
    }

    identities =
      visit_blocks(document["blocks"] || [], identities, fn block, acc ->
        id = block["id"]

        if non_empty_string?(id) and not Map.has_key?(acc["evidence"], id) do
          put_in(acc, ["evidence", id], "AST block '#{id}'")
        else
          acc
        end
      end)

    {identities, diagnostics} =
      Enum.reduce(
        document["resources"] || [],
        {identities, diagnostics},
        fn resource, state ->
          register_document_identity(
            state,
            resource["id"],
            "evidence",
            "resource '#{resource["id"]}'"
          )
        end
      )

    {_identities, diagnostics} =
      visit_blocks(document["blocks"] || [], {identities, diagnostics}, fn block, state ->
        props = block["props"] || %{}

        state =
          if block["type"] in ["relay.source_bundle", "relay.evidence_ref"] and
               props["id"] != block["id"] do
            register_document_identity(
              state,
              props["id"],
              "evidence",
              "#{block["type"]}.props.id on block '#{block["id"]}'"
            )
          else
            state
          end

        if block["type"] == "relay.action_row" do
          Enum.reduce(
            [
              {"proposal_id", "proposal"},
              {"proposal_record_id", "proposal_record"},
              {"decision_id", "decision"},
              {"execution_id", "execution"},
              {"undo_id", "undo"}
            ],
            state,
            fn {field, namespace}, acc ->
              register_document_identity(
                acc,
                props[field],
                namespace,
                "relay.action_row.#{field} on block '#{block["id"]}'"
              )
            end
          )
        else
          state
        end
      end)

    diagnostics
  end

  defp register_document_identity({identities, diagnostics}, value, namespace, origin) do
    if non_empty_string?(value) do
      registry = identities[namespace]

      case Map.fetch(registry, value) do
        {:ok, prior} ->
          {identities,
           append_error(
             diagnostics,
             "relaymark.identity.duplicate_#{namespace}",
             "Identity '#{value}' is ambiguous between #{prior} and #{origin}."
           )}

        :error ->
          {Map.put(identities, namespace, Map.put(registry, value, origin)), diagnostics}
      end
    else
      {identities, diagnostics}
    end
  end

  defp visit_blocks(blocks, accumulator, visitor) do
    Enum.reduce(blocks, accumulator, fn block, acc ->
      acc = visitor.(block, acc)

      Enum.reduce(block["content"] || [], acc, fn child, child_acc ->
        if block_node?(child) do
          visit_blocks([child], child_acc, visitor)
        else
          child_acc
        end
      end)
    end)
  end

  defp evidence_refs_for(block) do
    cond do
      is_list(block["evidence_refs"]) and block["evidence_refs"] != [] ->
        block["evidence_refs"]

      is_list(get_in(block, ["props", "evidence"])) ->
        get_in(block, ["props", "evidence"])

      true ->
        []
    end
  end

  defp validate_attribute(type, name, value, %{"type" => "enum"} = attribute, diagnostics) do
    values = attribute["values"] || []

    if value in values do
      diagnostics
    else
      append_error(
        diagnostics,
        "relaymark.attribute.enum",
        "#{type}.#{name} must be one of #{Enum.join(values, ", ")}."
      )
    end
  end

  defp validate_attribute(type, name, value, %{"type" => "array"} = attribute, diagnostics) do
    cond do
      not is_list(value) ->
        append_error(
          diagnostics,
          "relaymark.attribute.array",
          "#{type}.#{name} must be an array."
        )

      attribute["items"] == "string" and Enum.any?(value, &(not is_binary(&1))) ->
        append_error(
          diagnostics,
          "relaymark.attribute.array_items",
          "#{type}.#{name} must contain only strings."
        )

      true ->
        diagnostics
    end
  end

  defp validate_attribute(type, name, value, %{"type" => "integer"}, diagnostics) do
    if is_integer(value) do
      diagnostics
    else
      append_error(
        diagnostics,
        "relaymark.attribute.integer",
        "#{type}.#{name} must be an integer."
      )
    end
  end

  defp validate_attribute(type, name, value, %{"type" => "number"}, diagnostics) do
    if is_number(value) do
      diagnostics
    else
      append_error(
        diagnostics,
        "relaymark.attribute.number",
        "#{type}.#{name} must be a number."
      )
    end
  end

  defp validate_attribute(type, name, value, %{"type" => "boolean"}, diagnostics) do
    if is_boolean(value) do
      diagnostics
    else
      append_error(
        diagnostics,
        "relaymark.attribute.boolean",
        "#{type}.#{name} must be a boolean."
      )
    end
  end

  defp validate_attribute(type, name, value, %{"type" => "object"}, diagnostics) do
    if is_map(value) do
      diagnostics
    else
      append_error(
        diagnostics,
        "relaymark.attribute.object",
        "#{type}.#{name} must be an object."
      )
    end
  end

  defp validate_attribute(type, name, value, %{"type" => "string"}, diagnostics) do
    if is_binary(value) do
      diagnostics
    else
      append_error(
        diagnostics,
        "relaymark.attribute.string",
        "#{type}.#{name} must be a string."
      )
    end
  end

  defp validate_attribute(_type, _name, _value, _attribute, diagnostics), do: diagnostics

  defp block_node?(node) when is_map(node) do
    is_binary(node["type"]) and not inline_node?(node)
  end

  defp block_node?(_node), do: false

  defp inline_node?(%{"type" => type}) when is_binary(type) do
    MapSet.member?(@commonmark_inline_types, type) or
      (String.starts_with?(type, "relay.") and String.ends_with?(type, "_ref") and
         not Map.has_key?(@directive_registry, type))
  end

  defp inline_node?(_node), do: false

  defp maybe_put_identity(set, value) do
    if non_empty_string?(value), do: MapSet.put(set, value), else: set
  end

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp append_error(diagnostics, code, message) do
    diagnostics ++ [Diagnostic.error(code, message)]
  end
end
