defmodule RelayMark.ContentEdit do
  @moduledoc """
  Maintained ProseMirror/Yjs execution and ephemeral command proof over the canonical editor schema.

  Hosts supply an admitted pre-document, prove CRDT anchors/frontiers and copies,
  and own runtime supervision/pooling. This module owns no durable editable document replica,
  authorization, transport or global serial runtime. Each runtime has a bounded
  isolated QuickJS-NG thread. Resource refusal never invokes another interpreter.
  """

  @limits [timeout: 1_000, memory_limit: 67_108_864, max_stack_size: 2_097_152]

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

  @doc "Replay actual maintained PM/Yjs command and compare its complete original mutation footprint. Optional private accepted-owner receipts reconstruct the same maintained UndoManager for inverse correspondence. Hosts still authorize source, scope, receipt membership and accepted undo/redo cycles."
  def replay_mutation(runtime, evidence) when is_map(evidence),
    do: execute_arguments(runtime, "replayContentEditMutation", [evidence])

  def replay_mutation(_, _), do: {:error, :invalid_content_edit}

  @doc "Produce one actual DOM-free maintained command from host-admitted retained state and trusted server command/manager identities. The host still authorizes and independently admits the original returned update."
  def produce(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "produceContentEdit", [input])

  def produce(_, _), do: {:error, :invalid_content_edit}

  @doc "Plan a complete canonical authored target through the same maintained command producer."
  def produce_document_patch(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "produceDocumentPatch", [input])

  def produce_document_patch(_, _), do: {:error, :invalid_content_edit}

  @doc "Checkpoint the actual maintained owner after trusted chronological command replay. The host owns scoped checkpoint persistence, coverage and immutable receipt authentication. No raw update archive is returned."
  def checkpoint_owned_history(runtime, input) when is_map(input),
    do: execute_arguments(runtime, "createOwnedHistoryCheckpoint", [input])

  def checkpoint_owned_history(_, _), do: {:error, :invalid_content_edit}

  @doc "Stateless classification after the host authenticates current original receipts, scope and complete proof. Inputs and results are not credentials."
  def classify_source_reference(runtime, binding, transaction, proof, human_ancestry),
    do:
      execute_source_arguments(runtime, "classifyContentEditReference", [
        binding,
        transaction,
        proof,
        human_ancestry
      ])

  @doc "Fold authenticated current references for only the requested candidate identities; tombstoned ancestors remain exact evidence."
  def fold_source_references(runtime, binding, candidate_selector, references),
    do:
      execute_source_arguments(runtime, "foldSourceReferences", [
        binding,
        candidate_selector,
        references
      ])

  @doc "Read current visible selector windows; no authorship or command admission is inferred."
  def source_selector_windows(runtime, snapshot),
    do: execute_arguments(runtime, "sourceSelectorWindows", [snapshot])

  @doc "Resolve validated current visible source ranges in document order."
  def resolve_text_items(runtime, snapshot, selector),
    do: execute_arguments(runtime, "resolveContentEditTextItems", [snapshot, selector])

  # Source errors are explicit portable codes. Exception text is never parsed.
  defp execute_source_arguments(runtime, function, values) do
    with {:ok, arguments} <- Jason.encode(values) do
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
    with {:ok, arguments} <- Jason.encode(values) do
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

  defp execute(runtime, function, document, operation)
       when is_map(document) and is_map(operation) do
    execute_arguments(runtime, function, [document, operation])
  end

  defp execute(_runtime, _function, _document, _operation), do: {:error, :invalid_content_edit}

  defp bundle_path do
    Path.join(:code.priv_dir(:relay_mark_elixir), "collaboration/content-edit-runtime.js")
  end
end
