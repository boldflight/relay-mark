defmodule RelayMark.DocumentImport do
  @moduledoc "Finite historical AST conversion, never a live editing/admission alternative."
  @ids ~r/^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$/
  @profiles %{
    "relaymark.agent_answer.v1" => "relaymark.agent_answer",
    "relaymark.scripture_release.v1" => "relaymark.scripture_release",
    "relaymark.scripture_span.v1" => "relaymark.scripture_span"
  }
  @inline ~w(text hard_break soft_break link emphasis strong strikethrough underline highlight superscript subscript code_span relay.entity_ref relay.tag_ref)
  def import(document, options \\ []) do
    namespace = Keyword.fetch!(options, :namespace)
    true = is_binary(namespace) and namespace != ""

    document =
      case Map.fetch(document, "version") do
        :error -> document
        {:ok, 1} -> Map.delete(document, "version")
        _ -> throw(:unknown_historical_version)
      end

    document = profiles(document)

    state = %{
      namespace: namespace,
      ids: %{},
      seen: MapSet.new(),
      mapping: %{"retained" => [], "remapped" => [], "added" => []}
    }

    {blocks, state} = Enum.map_reduce(document["blocks"], state, &block/2)
    document = document |> Map.put("blocks", blocks) |> references(state.ids)

    with {:ok, _} <- RelayMark.DocumentXML.from_document(document) do
      {:ok,
       %{
         document: document,
         identity_mapping: Map.new(state.mapping, fn {k, v} -> {k, Enum.reverse(v)} end)
       }}
    end
  rescue
    _ in [KeyError, MatchError, FunctionClauseError, ArgumentError, BadMapError] ->
      error(:historical_shape)
  catch
    reason -> error(reason)
  end

  defp error(reason),
    do:
      {:error,
       [%{"level" => "error", "code" => "relaymark.import.invalid", "reason" => inspect(reason)}]}

  defp profiles(list) when is_list(list), do: Enum.map(list, &profiles/1)

  defp profiles(map) when is_map(map),
    do:
      Map.new(map, fn {key, value} ->
        {key, if(key == "profile", do: Map.get(@profiles, value, value), else: profiles(value))}
      end)

  defp profiles(value), do: value

  defp block(node, state) do
    old = node["id"]

    if not is_binary(old) or old == "" or MapSet.member?(state.seen, old),
      do: throw(:historical_identity)

    {new, state} =
      if Regex.match?(@ids, old) do
        {old, update_in(state, [:mapping, "retained"], &[old | &1])}
      else
        new = identity(state.namespace, ["migration", "block", old])
        {new, update_in(state, [:mapping, "remapped"], &[%{"from" => old, "to" => new} | &1])}
      end

    state = %{state | ids: Map.put(state.ids, old, new), seen: MapSet.put(state.seen, old)}
    node = Map.put(node, "id", new)

    node =
      if Map.has_key?(node, "evidence_refs") do
        if not is_list(node["evidence_refs"]) or
             node["evidence_refs"] != get_in(node, ["props", "evidence"]),
           do: throw(:ambiguous_evidence)

        Map.delete(node, "evidence_refs")
      else
        node
      end

    {children, state} =
      Enum.map_reduce(Map.get(node, "content", []), state, fn child, s ->
        if child["type"] in @inline, do: {child, s}, else: block(child, s)
      end)

    {children, state} =
      if RelayMark.DocumentDirectives.spec(node["type"]),
        do: wrap(children, state, old, new),
        else: {children, state}

    {Map.put(node, "content", children), state}
  end

  defp wrap(children, state, old, parent) do
    {out, pending, state} =
      Enum.reduce(children, {[], [], state}, fn child, {out, pending, s} ->
        if child["type"] in @inline,
          do: {out, pending ++ [child], s},
          else:
            (
              {out, s} = flush(out, pending, s, old, parent)
              {out ++ [child], [], s}
            )
      end)

    flush(out, pending, state, old, parent)
  end

  defp flush(out, [], state, _, _), do: {out, state}

  defp flush(out, pending, state, old, parent) do
    index = length(out)
    id = identity(state.namespace, ["migration", old, "inline", Integer.to_string(index)])
    added = %{"id" => id, "parent" => parent, "role" => "inline_body", "index" => index}
    state = update_in(state, [:mapping, "added"], &[added | &1])
    {out ++ [%{"id" => id, "type" => "paragraph", "content" => pending}], state}
  end

  defp references(list, ids) when is_list(list), do: Enum.map(list, &references(&1, ids))

  defp references(map, ids) when is_map(map),
    do:
      Map.new(map, fn {key, value} ->
        updated =
          cond do
            key in ~w(block_id start_block_id end_block_id) and is_binary(value) ->
              Map.get(ids, value, value)

            key == "evidence" and is_list(value) ->
              Enum.map(value, &Map.get(ids, &1, &1))

            true ->
              references(value, ids)
          end

        {key, updated}
      end)

  defp references(value, _), do: value

  defp identity(namespace, path), do: RelayMark.DocumentIdentity.generate(namespace, path)
end
