defmodule RelayMark.ContentEdit do
  @moduledoc """
  Maintained ProseMirror/Yjs execution and ephemeral command proof over the canonical editor schema.

  Hosts supply an admitted pre-document, prove CRDT anchors/frontiers and copies,
  and own runtime supervision/pooling. This module owns no durable editable document replica,
  authorization, transport or global serial runtime. Each runtime has a bounded
  isolated QuickJS-NG thread. Resource refusal never invokes another interpreter.
  """

  # The unchanged131072-unit copy+ancestry classifier needs ~384MiB/4.7s
  # on the measured maintained QuickJS cohort. Hosts bound concurrent workers;
  # these are hard maxima, with explicit timeout/OOM refusal and no fallback.
  @limits [timeout: 10_000, memory_limit: 402_653_184, max_stack_size: 2_097_152]

  @doc "Start an isolated reusable runtime; the host must stop it when its owner exits."
  def start_runtime(opts \\ []) do
    with {:ok, runtime} <- Quicksand.start(Keyword.merge(@limits, opts)) do
      case Quicksand.eval(runtime, File.read!(bundle_path())) do
        {:ok, _} ->
          {:ok, runtime}

        {:error, _} ->
          Quicksand.stop(runtime)
          {:error, :content_edit_runtime_unavailable}
      end
    end
  end

  def stop_runtime(runtime), do: Quicksand.stop(runtime)

  @doc "Apply actual Step JSON to a host-admitted PM document using the maintained owner."
  def apply(runtime, document, operation),
    do: execute(runtime, "applyContentEdit", document, operation)

  @doc "Execute the same maintained steps from a host-admitted canonical AST, preserving its envelope."
  def apply_document(runtime, document, operation),
    do: execute(runtime, "applyDocumentContentEdit", document, operation)

  @doc "Prepare exact causal text/copy evidence. The result is not final mutation or history admission."
  def prepare_witness(runtime, evidence) when is_map(evidence) do
    execute_arguments(runtime, "prepareContentEditWitness", [evidence])
  end

  def prepare_witness(_, _), do: {:error, :invalid_content_edit}

  @doc "Derive exact relocation-copy and human selectors from maintained StepMaps and trusted identity snapshots."
  def build_witness(runtime, evidence) when is_map(evidence),
    do: execute_arguments(runtime, "buildContentEditWitness", [evidence])

  def build_witness(_, _), do: {:error, :invalid_content_edit}

  @doc "Allocate colliding imported Anchor names as actual maintained Steps while retaining all target destinations. No donor authority is issued."
  def plan_reviewed_anchor_allocation(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "planReviewedAnchorAllocation", [input])

  def plan_reviewed_anchor_allocation(_, _), do: {:error, :invalid_content_edit}

  @doc "Plan original-ordinal imported heading/link repairs as actual maintained Steps. No donor or receipt authority is issued."
  def plan_reviewed_heading_navigation(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "planReviewedHeadingNavigation", [input])

  def plan_reviewed_heading_navigation(_, _), do: {:error, :invalid_content_edit}

  @doc "Prove complete-block reviewed append regions against exact archived structure and actual fresh allocations. The host still authenticates archive hashes, target guard, donor ancestry and complete mutation correspondence."
  def prepare_reviewed_recovery_witness(runtime, evidence) when is_map(evidence),
    do: execute_arguments(runtime, "prepareReviewedRecoveryWitness", [evidence])

  def prepare_reviewed_recovery_witness(_, _), do: {:error, :invalid_content_edit}

  @doc "Recheck target-only regional allocations for an already authenticated original issued association. The host owns receipt/scope/archive authority and must independently prove complete mutation correspondence."
  def prepare_retained_reviewed_recovery_witness(runtime, evidence) when is_map(evidence),
    do: execute_arguments(runtime, "prepareRetainedReviewedRecoveryWitness", [evidence])

  def prepare_retained_reviewed_recovery_witness(_, _), do: {:error, :invalid_content_edit}

  @doc "Resolve only reviewed imported archive candidates; this issues no human or donor authority."
  def reviewed_recovery_source_selection(runtime, evidence) when is_map(evidence),
    do: execute_arguments(runtime, "reviewedRecoverySourceSelection", [evidence])

  def reviewed_recovery_source_selection(_, _), do: {:error, :invalid_content_edit}

  @doc "Map independently authenticated human archive candidates through recomputed structural recovery regions."
  def map_reviewed_recovery_selection(runtime, evidence) when is_map(evidence),
    do: execute_arguments(runtime, "mapReviewedRecoverySelection", [evidence])

  def map_reviewed_recovery_selection(_, _), do: {:error, :invalid_content_edit}

  @doc "Replay actual maintained PM/Yjs command and compare its complete original mutation footprint. Optional private accepted-owner receipts reconstruct the same maintained UndoManager for inverse correspondence. Hosts still authorize source, scope, receipt membership and accepted undo/redo cycles."
  def replay_mutation(runtime, evidence) when is_map(evidence),
    do: execute_arguments(runtime, "replayContentEditMutation", [evidence])

  def replay_mutation(_, _), do: {:error, :invalid_content_edit}

  @doc "Imports retained inert HTML through the maintained DOM and canonical editor grammar."
  def import_document_html(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "importDocumentHTML", [input])

  def import_document_html(_, _), do: {:error, :invalid_content_edit}

  @doc "Produce one actual DOM-free maintained command from host-admitted retained state and trusted server command/manager identities. The host still authorizes and independently admits the original returned update."
  def produce(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "produceContentEdit", [input])

  def produce(_, _), do: {:error, :invalid_content_edit}

  @doc "Produce one actual maintained undo/redo from host-authenticated original owner receipts or checkpoint."
  def produce_owned_history(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "produceOwnedHistory", [input])

  def produce_owned_history(_, _), do: {:error, :invalid_content_edit}

  @doc "Plan a complete canonical authored target through the same maintained command producer."
  def produce_document_patch(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "produceDocumentPatch", [input])

  def produce_document_patch(_, _), do: {:error, :invalid_content_edit}

  @doc "Plan one exact authored-text replacement as maintained Steps over canonical rich AST."
  def prepare_document_text_replacement(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "prepareDocumentTextReplacement", [input])

  def prepare_document_text_replacement(_, _), do: {:error, :invalid_content_edit}

  @doc "Read-only dependency planning across an authenticated complete actor/owner cut. The host authenticates original reviewed associations and the whole checkpoint sidecar; the plan grants no source or erasure authority."
  def plan_reviewed_recovery_retirement(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "planReviewedRecoveryRetirement", [input])

  def plan_reviewed_recovery_retirement(_, _), do: {:error, :invalid_content_edit}

  @doc "Retire authenticated complete owned groups through the actual reconstructed manager and capture its surviving checkpoint. Source classification and erasure authority remain with the host."
  def retire_owned_history(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "retireOwnedHistoryCheckpoint", [input])

  def retire_owned_history(_, _), do: {:error, :invalid_content_edit}

  @doc """
  Verifies or derives a finite physical/history cut through the maintained owner.

  Supply exactly the conversion update/destination state pair, or `writer_client`
  alone. The writer must be a fresh uint32 absent from the complete original
  client roster; null is allowed only for a proved zero-effect transform. Original
  basis, receipts and owner/cohort requirements are unchanged. Derivation adds
  the independently verified `conversion_update_base64` to the existing result.

  Reviewed cohorts use the same privately recognized aggregate/per-field input
  and exact Video/Slot plans; the Video array may be empty. Internal conditional
  field/option relations affect capability closure only, never typed ancestry.
  Option predecessors validate placement without becoming capability sources.

  The host authenticates the complete original inventory and consumes the actual
  state and manager result. No receipt, source authority, installation permission
  or live historical codec fallback is supplied. Prior physical-cut/terminal
  continuity and actual host installation require separate qualification.
  """
  def prepare_aggregate_settings_history_cut(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "prepareAggregateSettingsHistoryCut", [input])

  def prepare_aggregate_settings_history_cut(_, _), do: {:error, :invalid_content_edit}

  @doc "Checkpoint the actual maintained owner after trusted chronological command replay. The host owns scoped checkpoint persistence, coverage and immutable receipt authentication. No raw update archive is returned."
  def checkpoint_owned_history(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "createOwnedHistoryCheckpoint", [input])

  def checkpoint_owned_history(_, _), do: {:error, :invalid_content_edit}

  @doc "Stateless classification after the host authenticates current original receipts, scope and complete proof. Inputs and results are not credentials."
  def classify_source_reference(
        runtime,
        binding,
        transaction,
        proof,
        human_ancestry,
        regional_context \\ nil
      ),
      do:
        execute_source_arguments(
          runtime,
          "classifyContentEditReference",
          [
            binding,
            transaction,
            proof,
            human_ancestry
          ] ++ if(is_nil(regional_context), do: [], else: [regional_context])
        )

  @doc "Fold authenticated current references for only the requested candidate identities; tombstoned ancestors remain exact evidence."
  def fold_source_references(
        runtime,
        binding,
        candidate_selector,
        references,
        regional_contexts \\ nil
      ),
      do:
        execute_source_arguments(
          runtime,
          "foldSourceReferences",
          [
            binding,
            candidate_selector,
            references
          ] ++ if(is_nil(regional_contexts), do: [], else: [regional_contexts])
        )

  @doc "Subtract authenticated erasure summary intervals from one bounded candidate selector. No admission or ancestry authority is granted."
  def subtract_source_selectors(runtime, candidates, excluded),
    do: execute_source_arguments(runtime, "subtractSourceSelectors", [candidates, excluded])

  @doc "Partition recomputed imported destinations using separately authenticated human/generated subsets. Unproven remainder is unknown; inputs confer no authority."
  def partition_reviewed_recovery_destinations(runtime, input),
    do: execute_source_arguments(runtime, "partitionReviewedRecoveryDestinations", [input])

  @doc "Read current visible selector windows; no authorship or command admission is inferred."
  def source_selector_windows(runtime, snapshot),
    do: execute_arguments(runtime, "sourceSelectorWindows", [snapshot])

  @doc "Read original finite archive candidate windows; the host authenticates the file and every source claim."
  def reviewed_recovery_archive_source_windows(runtime, evidence) when is_map(evidence),
    do: execute_arguments(runtime, "reviewedRecoveryArchiveSourceWindows", [evidence])

  def reviewed_recovery_archive_source_windows(_, _), do: {:error, :invalid_content_edit}

  @doc "Resolve validated current visible source ranges in document order."
  def resolve_text_items(runtime, snapshot, selector),
    do: execute_arguments(runtime, "resolveContentEditTextItems", [snapshot, selector])

  # Source errors are explicit portable codes. Exception text is never parsed.
  defp execute_source_arguments(runtime, function, values) do
    with {:ok, arguments} <- encode_arguments(values) do
      code =
        "(()=>{try{return {value:RelayMarkContentEditRuntime." <>
          function <>
          "(..." <>
          arguments <>
          ")}}catch(error){return {source_error:error.code||'source_reference_mismatch'}}})()"

      case Quicksand.eval(runtime, code) do
        {:ok, %{"value" => value}} when is_map(value) ->
          {:ok, value}

        {:ok, %{"source_error" => "source_identity_mismatch"}} ->
          {:error, :source_identity_mismatch}

        {:ok, %{"source_error" => "source_identity_limit"}} ->
          {:error, :source_identity_limit}

        {:error, "timeout"} ->
          {:error, :source_identity_limit}

        _ ->
          {:error, :source_reference_mismatch}
      end
    else
      _ -> {:error, :source_reference_mismatch}
    end
  end

  defp execute_arguments(runtime, function, values) do
    with {:ok, arguments} <- encode_arguments(values) do
      code = "RelayMarkContentEditRuntime." <> function <> "(..." <> arguments <> ")"

      case Quicksand.eval(runtime, code) do
        {:ok, result} when is_map(result) -> {:ok, result}
        {:error, "timeout"} -> {:error, :content_edit_timeout}
        _ -> {:error, :invalid_content_edit}
      end
    else
      _ -> {:error, :invalid_content_edit}
    end
  end

  # Preserve JSON own keys rather than interpreting objects as JS literals.
  # Both facade paths keep their existing classification/resource boundaries.
  defp encode_arguments(values) do
    with {:ok, arguments} <- Jason.encode(values),
         {:ok, quoted} <- Jason.encode(arguments) do
      {:ok, "JSON.parse(" <> quoted <> ")"}
    end
  end

  defp execute(runtime, function, document, operation)
       when is_map(document) and is_map(operation) do
    execute_arguments(runtime, function, [document, operation])
  end

  defp execute(_runtime, _function, _document, _operation), do: {:error, :invalid_content_edit}

  @doc "Exact maintained interpreter bytes used to qualify finite conversion receipts."
  def runtime_digest,
    do: Base.encode16(:crypto.hash(:sha256, File.read!(bundle_path())), case: :lower)

  defp bundle_path do
    Path.join(:code.priv_dir(:relay_mark_elixir), "collaboration/content-edit-runtime.js")
  end
end
