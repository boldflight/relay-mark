defmodule RelayMark.ContentEdit do
  @moduledoc """
  Pure maintained ProseMirror step execution over the canonical editor schema.

  Hosts supply an admitted pre-document, prove CRDT anchors/frontiers and copies,
  and own runtime supervision/pooling. This module owns no document replica,
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

  defp execute(runtime, function, document, operation)
       when is_map(document) and is_map(operation) do
    with {:ok, arguments} <- Jason.encode([document, operation]) do
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

  defp execute(_runtime, _function, _document, _operation), do: {:error, :invalid_content_edit}

  defp bundle_path do
    Path.join(:code.priv_dir(:relay_mark_elixir), "collaboration/content-edit-runtime.js")
  end
end
