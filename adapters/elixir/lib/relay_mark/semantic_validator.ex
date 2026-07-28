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

  @directive_paths Path.expand("../../priv/relaymark/directives/*.json", __DIR__)
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

  @spec validate(map(), map()) :: [Diagnostic.t()]
  def validate(document, validation_context \\ %{})
      when is_map(document) and is_map(validation_context) do
    diagnostics =
      []
      |> validate_document_type(document)
      |> validate_document_version(document)

    evidence_targets = collect_evidence_targets(document)
    scripture_resources = collect_scripture_resources(document)
    diagnostics = validate_scripture_resources(document, diagnostics)

    {diagnostics, _seen_ids} =
      Enum.reduce(document["blocks"] || [], {diagnostics, MapSet.new()}, fn block, state ->
        validate_block(block, state, evidence_targets, scripture_resources)
      end)

    diagnostics = validate_agent_answer_profile(document, diagnostics, validation_context)
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

  defp validate_block(block, {diagnostics, seen_ids}, evidence_targets, scripture_resources) do
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
        validate_relay_block(block, diagnostics, evidence_targets, scripture_resources)
      else
        diagnostics
      end

    Enum.reduce(block["content"] || [], {diagnostics, seen_ids}, fn child, state ->
      if block_node?(child) do
        validate_block(child, state, evidence_targets, scripture_resources)
      else
        state
      end
    end)
  end

  defp validate_relay_block(block, diagnostics, evidence_targets, scripture_resources) do
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
            "relay.action_row" ->
              validate_action_proposal(block, diagnostics)

            "relay.source_bundle" ->
              validate_source_bundle(block, diagnostics)

            "relay.evidence_ref" ->
              validate_evidence_ref(block, diagnostics, scripture_resources)

            "relay.claim" ->
              validate_claim(block, diagnostics)

            "relay.comparison" ->
              validate_comparison(block, diagnostics)

            _other ->
              diagnostics
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

  defp validate_evidence_ref(block, diagnostics, scripture_resources) do
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

    diagnostics =
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

    if props["source_type"] == "scripture" do
      validate_scripture_evidence_ref(block, scripture_resources, diagnostics)
    else
      diagnostics
    end
  end

  defp validate_scripture_resources(document, diagnostics) do
    Enum.reduce(document["resources"] || [], diagnostics, fn resource, acc ->
      if resource["type"] == "scripture" do
        validate_scripture_resource(resource, acc)
      else
        acc
      end
    end)
  end

  defp validate_scripture_resource(resource, diagnostics) do
    props = resource["props"] || %{}

    diagnostics =
      Enum.reduce(
        [
          "profile",
          "translation_id",
          "edition_id",
          "corpus_release_id",
          "versification_id",
          "attribution"
        ],
        diagnostics,
        fn field, acc ->
          if non_empty_string?(props[field]) do
            acc
          else
            append_error(
              acc,
              "relaymark.scripture.release",
              "scripture resource '#{resource["id"] || "unknown"}' requires #{field}."
            )
          end
        end
      )

    diagnostics =
      if props["profile"] == "relaymark.scripture_release.v1" do
        diagnostics
      else
        append_error(
          diagnostics,
          "relaymark.scripture.release_profile",
          "scripture resource '#{resource["id"] || "unknown"}' must use relaymark.scripture_release.v1."
        )
      end

    diagnostics
    |> validate_required_string_object(
      props["source"],
      ["name", "uri", "digest"],
      "source",
      resource["id"]
    )
    |> validate_required_string_object(
      props["license"],
      ["id", "name", "url"],
      "license",
      resource["id"]
    )
    |> validate_required_string_object(
      props["provenance"],
      ["coordinate_inventory_digest", "normalized_index_input_digest"],
      "provenance",
      resource["id"]
    )
    |> validate_scripture_digest(
      nested_value(props["source"], "digest"),
      "source.digest",
      resource["id"]
    )
    |> validate_scripture_digest(
      nested_value(props["provenance"], "coordinate_inventory_digest"),
      "provenance.coordinate_inventory_digest",
      resource["id"]
    )
    |> validate_scripture_digest(
      nested_value(props["provenance"], "normalized_index_input_digest"),
      "provenance.normalized_index_input_digest",
      resource["id"]
    )
    |> validate_optional_scripture_digest(
      nested_value(props["provenance"], "source_archive_digest"),
      "provenance.source_archive_digest",
      resource["id"]
    )
    |> validate_scripture_resource_scope(resource)
  end

  defp validate_scripture_resource_scope(diagnostics, resource) do
    if resource["scope"] in ["private", "org", "unlisted", "public"] do
      diagnostics
    else
      append_error(
        diagnostics,
        "relaymark.scripture.release_scope",
        "scripture resource '#{resource["id"] || "unknown"}' requires an explicit valid scope."
      )
    end
  end

  defp validate_required_string_object(diagnostics, value, fields, label, resource_id)
       when is_map(value) do
    Enum.reduce(fields, diagnostics, fn field, acc ->
      if non_empty_string?(value[field]) do
        acc
      else
        append_error(
          acc,
          "relaymark.scripture.release",
          "scripture resource '#{resource_id || "unknown"}' requires #{label}.#{field}."
        )
      end
    end)
  end

  defp validate_required_string_object(diagnostics, _value, _fields, label, resource_id) do
    append_error(
      diagnostics,
      "relaymark.scripture.release",
      "scripture resource '#{resource_id || "unknown"}' requires a #{label} object."
    )
  end

  defp validate_scripture_digest(diagnostics, value, field, resource_id) do
    if sha256_digest?(value) do
      diagnostics
    else
      append_error(
        diagnostics,
        "relaymark.scripture.digest",
        "scripture resource '#{resource_id || "unknown"}' requires #{field} as a lowercase sha256 digest."
      )
    end
  end

  defp validate_optional_scripture_digest(diagnostics, nil, _field, _resource_id),
    do: diagnostics

  defp validate_optional_scripture_digest(diagnostics, value, field, resource_id) do
    validate_scripture_digest(diagnostics, value, field, resource_id)
  end

  defp validate_scripture_evidence_ref(block, scripture_resources, diagnostics) do
    props = block["props"] || %{}
    matches = Map.get(scripture_resources, props["source"], [])

    case matches do
      [resource] ->
        release = resource["props"] || %{}

        diagnostics =
          if props["source_revision"] == release["corpus_release_id"] do
            diagnostics
          else
            append_error(
              diagnostics,
              "relaymark.scripture.source_revision",
              "relay.evidence_ref.source_revision must equal the scripture resource corpus_release_id."
            )
          end

        diagnostics =
          if scope_allows?(resource["scope"], props["scope"]) do
            diagnostics
          else
            append_error(
              diagnostics,
              "relaymark.scripture.scope",
              "relay.evidence_ref scope must not be broader than its scripture resource scope."
            )
          end

        validate_scripture_selector(block, diagnostics)

      _other ->
        append_error(
          diagnostics,
          "relaymark.scripture.source_resolution",
          "relay.evidence_ref scripture source '#{props["source"] || ""}' must resolve to exactly one scripture resource."
        )
    end
  end

  defp validate_scripture_selector(block, diagnostics) do
    selector = get_in(block, ["props", "selector"])

    if is_map(selector) do
      diagnostics =
        if selector["profile"] == "relaymark.scripture_span.v1" do
          diagnostics
        else
          append_error(
            diagnostics,
            "relaymark.scripture.selector_profile",
            "Scripture evidence selector must use relaymark.scripture_span.v1."
          )
        end

      {diagnostics, start_valid} =
        validate_scripture_coordinate(selector["start"], "start", diagnostics)

      {diagnostics, end_valid} =
        validate_scripture_coordinate(selector["end"], "end", diagnostics)

      diagnostics =
        if start_valid and end_valid and
             (selector["start"]["book_id"] != selector["end"]["book_id"] or
                selector["start"]["coordinate_kind"] != selector["end"]["coordinate_kind"]) do
          append_error(
            diagnostics,
            "relaymark.scripture.span_boundary",
            "Scripture span start and end must use the same book and coordinate kind."
          )
        else
          diagnostics
        end

      diagnostics =
        if sha256_digest?(selector["content_digest"]) do
          diagnostics
        else
          append_error(
            diagnostics,
            "relaymark.scripture.content_digest",
            "Scripture evidence requires a lowercase sha256 content_digest."
          )
        end

      if block_plain_text(block) |> non_empty_string?() do
        diagnostics
      else
        append_error(
          diagnostics,
          "relaymark.scripture.excerpt",
          "Scripture evidence requires a non-empty exact excerpt."
        )
      end
    else
      append_error(
        diagnostics,
        "relaymark.scripture.selector",
        "Scripture evidence requires a scripture span selector."
      )
    end
  end

  defp validate_scripture_coordinate(coordinate, endpoint, diagnostics) when is_map(coordinate) do
    common_valid =
      non_empty_string?(coordinate["book_id"]) and non_empty_string?(coordinate["verse_label"])

    shape_valid =
      case coordinate["coordinate_kind"] do
        "chapter" ->
          is_integer(coordinate["chapter"]) and coordinate["chapter"] > 0 and
            not Map.has_key?(coordinate, "section_id")

        "section" ->
          non_empty_string?(coordinate["section_id"]) and
            not Map.has_key?(coordinate, "chapter")

        _other ->
          false
      end

    if common_valid and shape_valid do
      {diagnostics, true}
    else
      {append_error(
         diagnostics,
         "relaymark.scripture.coordinate",
         "Scripture selector #{endpoint} must be a lossless chapter or section coordinate with a string verse_label."
       ), false}
    end
  end

  defp validate_scripture_coordinate(_coordinate, endpoint, diagnostics) do
    {append_error(
       diagnostics,
       "relaymark.scripture.coordinate",
       "Scripture selector #{endpoint} must be a coordinate object."
     ), false}
  end

  defp collect_scripture_resources(document) do
    Enum.reduce(document["resources"] || [], %{}, fn resource, acc ->
      if resource["type"] == "scripture" and non_empty_string?(resource["id"]) do
        Map.update(acc, resource["id"], [resource], &[resource | &1])
      else
        acc
      end
    end)
  end

  defp scope_allows?(resource_scope, evidence_scope) do
    ranks = %{"private" => 0, "org" => 1, "unlisted" => 2, "public" => 3}

    Map.has_key?(ranks, resource_scope) and Map.has_key?(ranks, evidence_scope) and
      ranks[evidence_scope] <= ranks[resource_scope]
  end

  defp block_plain_text(node) when is_list(node) do
    Enum.map_join(node, "", &block_plain_text/1)
  end

  defp block_plain_text(%{"type" => "text"} = node), do: node["text"] || ""

  defp block_plain_text(%{"content" => content}) when is_list(content) do
    block_plain_text(content)
  end

  defp block_plain_text(_node), do: ""

  defp validate_claim(block, diagnostics) do
    confidence = get_in(block, ["props", "confidence"])

    if is_number(confidence) and
         (not finite_number?(confidence) or confidence < 0 or confidence > 1) do
      append_error(
        diagnostics,
        "relaymark.claim.confidence_range",
        "relay.claim.confidence must be between 0.0 and 1.0."
      )
    else
      diagnostics
    end
  end

  defp validate_agent_answer_profile(document, diagnostics, validation_context) do
    frontmatter = document["frontmatter"] || %{}

    if frontmatter["profile"] == "relaymark.agent_answer.v1" do
      diagnostics =
        if non_empty_string?(frontmatter["title"]) do
          diagnostics
        else
          append_error(
            diagnostics,
            "relaymark.agent_answer.title",
            "relaymark.agent_answer.v1 requires a non-empty title."
          )
        end

      diagnostics =
        if frontmatter["scope"] in ["private", "org", "unlisted", "public"] do
          diagnostics
        else
          append_error(
            diagnostics,
            "relaymark.agent_answer.scope",
            "relaymark.agent_answer.v1 requires an explicit private, org, unlisted, or public scope."
          )
        end

      diagnostics =
        if non_empty_string?(frontmatter["question"]) do
          expected_question_id =
            "sha256:" <>
              (:crypto.hash(:sha256, frontmatter["question"])
               |> Base.encode16(case: :lower))

          if frontmatter["question_id"] == expected_question_id do
            diagnostics
          else
            append_error(
              diagnostics,
              "relaymark.agent_answer.question_id",
              "relaymark.agent_answer.v1 question_id must be the lowercase SHA-256 digest of the exact question UTF-8 bytes."
            )
          end
        else
          append_error(
            diagnostics,
            "relaymark.agent_answer.question",
            "relaymark.agent_answer.v1 requires a non-empty exact question."
          )
        end

      case frontmatter["outcome"] do
        "answered" ->
          validate_answered_agent_paper(document, diagnostics, validation_context)

        "refused" ->
          validate_refused_agent_paper(document, diagnostics)

        _other ->
          append_error(
            diagnostics,
            "relaymark.agent_answer.outcome",
            "relaymark.agent_answer.v1 outcome must be answered or refused."
          )
      end
    else
      diagnostics
    end
  end

  defp validate_answered_agent_paper(document, diagnostics, validation_context) do
    blocks = document["blocks"] || []

    evidence_heading_index =
      Enum.find_index(blocks, fn block ->
        heading_level(block) == 2 and block_plain_text(block) == "Evidence"
      end)

    claims =
      if is_integer(evidence_heading_index) and evidence_heading_index > 1 do
        Enum.slice(blocks, 1, evidence_heading_index - 1)
      else
        []
      end

    source_bundles =
      if is_integer(evidence_heading_index) do
        Enum.drop(blocks, evidence_heading_index + 1)
      else
        []
      end

    {level_one_heading_count, level_two_heading_count} =
      visit_blocks(blocks, {0, 0}, fn block, {level_one_count, level_two_count} ->
        {
          if(heading_level(block) == 1, do: level_one_count + 1, else: level_one_count),
          if(heading_level(block) == 2, do: level_two_count + 1, else: level_two_count)
        }
      end)

    structure_valid =
      length(blocks) >= 4 and heading_level(List.first(blocks)) == 1 and
        level_one_heading_count == 1 and level_two_heading_count == 1 and claims != [] and
        Enum.all?(claims, &(&1["type"] == "relay.claim")) and source_bundles != [] and
        Enum.all?(source_bundles, &(&1["type"] == "relay.source_bundle"))

    diagnostics =
      if structure_valid do
        diagnostics
      else
        append_error(
          diagnostics,
          "relaymark.agent_answer.answered_structure",
          "An answered relaymark.agent_answer.v1 paper requires one level-one heading, supported claims, an Evidence level-two heading, and source bundles in that order."
        )
      end

    {evidence_counts, evidence_blocks} =
      source_bundles
      |> Enum.filter(&(&1["type"] == "relay.source_bundle"))
      |> Enum.reduce({%{}, %{}}, fn source_bundle, state ->
        visit_blocks([source_bundle], state, fn block, {counts, blocks_by_id} ->
          evidence_id = get_in(block, ["props", "id"])

          if block["type"] == "relay.evidence_ref" and non_empty_string?(evidence_id) do
            {
              Map.update(counts, evidence_id, 1, &(&1 + 1)),
              Map.update(blocks_by_id, evidence_id, [block], &[block | &1])
            }
          else
            {counts, blocks_by_id}
          end
        end)
      end)

    diagnostics =
      claims
      |> Enum.filter(&(&1["type"] == "relay.claim"))
      |> Enum.reduce(diagnostics, fn claim, acc ->
        props = claim["props"] || %{}
        evidence_refs = evidence_refs_for(claim)

        acc =
          if non_empty_string?(props["key"]) and props["status"] == "supported" and
               non_empty_string?(block_plain_text(claim)) do
            acc
          else
            append_error(
              acc,
              "relaymark.agent_answer.claim",
              "Answered claim '#{claim["id"] || "unknown"}' requires a non-empty key and text with supported status."
            )
          end

        unique_refs = MapSet.new(evidence_refs)

        if evidence_refs != [] and MapSet.size(unique_refs) == length(evidence_refs) and
             Enum.all?(evidence_refs, fn reference ->
               non_empty_string?(reference) and Map.get(evidence_counts, reference, 0) == 1
             end) do
          acc
        else
          append_error(
            acc,
            "relaymark.agent_answer.claim_evidence",
            "Answered claim '#{claim["id"] || "unknown"}' must cite one or more unique concrete evidence refs that each resolve exactly once inside the paper's source bundles."
          )
        end
      end)

    diagnostics =
      if validation_surface(validation_context) == "scripture_ask" and
           Enum.any?(
             Enum.filter(claims, &(&1["type"] == "relay.claim")),
             fn claim ->
               Enum.any?(evidence_refs_for(claim), fn reference ->
                 case Map.get(evidence_blocks, reference, []) do
                   [%{"props" => %{"source_type" => "scripture"}}] -> false
                   _other -> true
                 end
               end)
             end
           ) do
        append_error(
          diagnostics,
          "relaymark.agent_answer.scripture_evidence",
          "A Scripture Ask host context requires every answered claim evidence ref to resolve to relay.evidence_ref source_type scripture."
        )
      else
        diagnostics
      end

    contains_forbidden_block =
      visit_blocks(blocks, false, fn block, found ->
        found or block["type"] in ["relay.agent_suggestion", "relay.action_row"]
      end)

    diagnostics =
      if contains_forbidden_block do
        append_error(
          diagnostics,
          "relaymark.agent_answer.read_only",
          "An answered relaymark.agent_answer.v1 paper must not contain agent suggestions or action rows."
        )
      else
        diagnostics
      end

    if Map.has_key?(document["frontmatter"] || %{}, "refusal_reason") do
      append_error(
        diagnostics,
        "relaymark.agent_answer.refusal_reason",
        "An answered relaymark.agent_answer.v1 paper must not contain refusal_reason."
      )
    else
      diagnostics
    end
  end

  defp validate_refused_agent_paper(document, diagnostics) do
    blocks = document["blocks"] || []

    {nested_block_count, level_one_heading_count} =
      visit_blocks(blocks, {0, 0}, fn block, {block_count, heading_count} ->
        {
          block_count + 1,
          if(heading_level(block) == 1, do: heading_count + 1, else: heading_count)
        }
      end)

    diagnostics =
      if get_in(document, ["frontmatter", "refusal_reason"]) == "insufficient_evidence" do
        diagnostics
      else
        append_error(
          diagnostics,
          "relaymark.agent_answer.refusal_reason",
          "A refused relaymark.agent_answer.v1 paper requires refusal_reason insufficient_evidence."
        )
      end

    explanation = Enum.at(blocks, 1)

    structure_valid =
      length(blocks) == 2 and nested_block_count == 2 and
        heading_level(List.first(blocks)) == 1 and level_one_heading_count == 1 and
        block_plain_text(List.first(blocks)) == "Answer unavailable" and
        explanation["type"] == "paragraph" and non_empty_string?(block_plain_text(explanation))

    diagnostics =
      if structure_valid do
        diagnostics
      else
        append_error(
          diagnostics,
          "relaymark.agent_answer.refused_structure",
          "A refused relaymark.agent_answer.v1 paper requires only an Answer unavailable level-one heading followed by one non-empty explanation paragraph."
        )
      end

    forbidden_types = [
      "relay.claim",
      "relay.source_bundle",
      "relay.evidence_ref",
      "relay.agent_suggestion",
      "relay.action_row"
    ]

    contains_forbidden_block =
      visit_blocks(blocks, false, fn block, found ->
        found or block["type"] in forbidden_types
      end)

    if contains_forbidden_block or (document["resources"] || []) != [] do
      append_error(
        diagnostics,
        "relaymark.agent_answer.refused_content",
        "A refused relaymark.agent_answer.v1 paper must not contain claims, sources, resources, evidence, suggestions, or actions."
      )
    else
      diagnostics
    end
  end

  defp heading_level(%{"type" => "heading", "props" => %{"level" => level}})
       when is_integer(level),
       do: level

  defp heading_level(%{"type" => "heading", "props" => %{"level" => level}})
       when is_float(level) and trunc(level) == level,
       do: trunc(level)

  defp heading_level(_block), do: nil

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

  defp validation_surface(validation_context) do
    validation_context["surface"] || validation_context[:surface]
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

  defp nested_value(value, key) when is_map(value), do: value[key]
  defp nested_value(_value, _key), do: nil

  defp non_empty_string?(value) when is_binary(value) do
    value
    |> String.to_charlist()
    |> Enum.any?(&(not relaymark_whitespace?(&1)))
  end

  defp non_empty_string?(_value), do: false

  defp relaymark_whitespace?(codepoint)
       when codepoint in 0x0009..0x000D or codepoint in 0x2000..0x200A,
       do: true

  defp relaymark_whitespace?(codepoint)
       when codepoint in [
              0x0020,
              0x0085,
              0x00A0,
              0x1680,
              0x2028,
              0x2029,
              0x202F,
              0x205F,
              0x3000
            ],
       do: true

  defp relaymark_whitespace?(_codepoint), do: false

  defp finite_number?(value) when is_integer(value), do: true

  defp finite_number?(value) when is_float(value) do
    value
    |> :erlang.float_to_binary([:compact])
    |> then(&(&1 not in ["nan", "inf", "-inf"]))
  end

  defp sha256_digest?(value) when is_binary(value) do
    Regex.match?(~r/^sha256:[0-9a-f]{64}$/, value)
  end

  defp sha256_digest?(_value), do: false

  defp append_error(diagnostics, code, message) do
    diagnostics ++ [Diagnostic.error(code, message)]
  end
end
