defmodule RelayMark.FormPublicationImport do
  @moduledoc "Finite saved publication input, never an editor, publishing or respondent owner."
  def import(publication, options \\ []) do
    namespace = Keyword.fetch!(options, :namespace)

    unless is_binary(namespace) and namespace != "" and is_map(publication) and
             is_list(publication["blocks"]), do: throw(:publication_shape)

    {blocks, mapping, normalizations, _seen} =
      Enum.reduce(
        Enum.with_index(publication["blocks"]),
        {[], empty_mapping(), [], MapSet.new()},
        fn {raw, position}, {blocks, mapping, normalizations, seen} ->
          if raw["type"] == "paragraph" do
            unless Enum.all?(Map.keys(raw), &(&1 in ~w(type label))),
              do: throw(:publication_prose_fields)

            {parsed, imported} =
              source(raw["label"], namespace <> ":publication:prose:" <> to_string(position))

            {blocks ++ parsed, combine(mapping, imported),
             normalizations ++
               [
                 %{
                   "path" => ["blocks", position],
                   "operation" => "import_source",
                   "block_ids" => Enum.map(parsed, & &1["id"])
                 }
               ], seen}
          else
            question_id = raw["id"]

            unless is_binary(question_id) and question_id != "" and
                     not MapSet.member?(seen, question_id),
                   do: throw(:publication_question_identity)

            id =
              RelayMark.DocumentIdentity.generate(namespace, ["publication", position, "question"])

            {label, label_mapping} =
              inline(
                Map.get(raw, "label", ""),
                namespace <> ":publication:" <> Jason.encode!(["label", question_id])
              )

            props = %{
              "id" => question_id,
              "type" => raw["type"],
              "required" => Map.get(raw, "required", false),
              "points" => raw["points"],
              "min" => raw["min"],
              "max" => raw["max"],
              "settings" => settings(raw, ~w(id type label required points min max options))
            }

            options = Map.get(raw, "options", [])
            unless is_list(options), do: throw(:publication_options)

            {choices, option_mapping, _} =
              Enum.reduce(Enum.with_index(options), {[], [], MapSet.new()}, fn {option, index},
                                                                               {choices, added,
                                                                                seen_options} ->
                option_id = option["id"]

                unless is_binary(option_id) and option_id != "" and
                         not MapSet.member?(seen_options, option_id),
                       do: throw(:publication_option_identity)

                if Map.has_key?(option, "label") and Map.has_key?(option, "text") and
                     option["label"] != option["text"], do: throw(:publication_option_label)

                {label, _} =
                  inline(
                    Map.get(option, "label", Map.get(option, "text", "")),
                    namespace <>
                      ":publication:" <> Jason.encode!(["option", question_id, option_id])
                  )

                block_id =
                  RelayMark.DocumentIdentity.generate(namespace, [
                    "publication",
                    position,
                    "option",
                    index
                  ])

                props = %{
                  "id" => option_id,
                  "correct" => Map.get(option, "correct", false),
                  "points" => option["points"],
                  "settings" => settings(option, ~w(id label text correct points))
                }

                choice = %{
                  "id" => block_id,
                  "type" => "relay.form_option",
                  "props" => props,
                  "content" => label["content"]
                }

                {choices ++ [choice],
                 added ++
                   [
                     %{
                       "id" => block_id,
                       "parent" => question_id,
                       "role" => "option",
                       "option_id" => option_id
                     }
                   ], MapSet.put(seen_options, option_id)}
              end)

            question = %{
              "id" => id,
              "type" => "relay.form_question",
              "props" => props,
              "content" => [label | choices]
            }

            grading!(question)

            mapping =
              combine(mapping, label_mapping)
              |> Map.update!(
                "added",
                &(&1 ++
                    option_mapping ++
                    [%{"id" => id, "role" => "question", "question_id" => question_id}])
              )

            change = %{
              "path" => ["blocks", position],
              "operation" => "form_question",
              "block_id" => id,
              "label_id" => label["id"],
              "option_ids" => Enum.map(choices, & &1["id"])
            }

            {blocks ++ [question], mapping, normalizations ++ [change],
             MapSet.put(seen, question_id)}
          end
        end
      )

    {blocks, mapping} =
      if blocks == [] do
        {parsed, imported} = source("", namespace <> ":publication:empty")
        {parsed, combine(mapping, imported)}
      else
        {blocks, mapping}
      end

    with {:ok, document} <-
           RelayMark.DocumentXML.normalize_document(%{
             "type" => "relaymark.document",
             "blocks" => blocks
           }) do
      result = %{document: document, identity_mapping: mapping, normalizations: normalizations}

      if Keyword.has_key?(options, :source),
        do: reconcile(result, Keyword.fetch!(options, :source), namespace),
        else: {:ok, result}
    end
  rescue
    _ -> error(:publication_shape)
  catch
    {:diagnostics, diagnostics} -> {:error, diagnostics}
    reason -> error(reason)
  end

  defp source(text, namespace) when is_binary(text) do
    case RelayMark.DocumentSource.import_source(text, namespace: namespace) do
      {:ok, %{document: document, identity_mapping: mapping}} ->
        unless Enum.all?(Map.keys(document), &(&1 in ~w(type blocks))),
          do: throw(:publication_fragment_metadata)

        {document["blocks"], mapping}

      {:error, diagnostics} ->
        throw({:diagnostics, diagnostics})
    end
  end

  defp source(_, _), do: throw(:publication_source)

  defp inline(text, namespace) do
    case source(text, namespace) do
      {[%{"type" => "paragraph"} = label], mapping} -> {label, mapping}
      _ -> throw(:publication_inline_label)
    end
  end

  defp empty_mapping, do: %{"retained" => [], "remapped" => [], "added" => []}

  defp combine(left, right),
    do: Map.new(left, fn {key, values} -> {key, values ++ right[key]} end)

  defp settings(block, known) do
    settings = Map.get(block, "settings", %{})
    unless is_map(settings), do: throw(:publication_settings)

    Enum.reduce(Map.drop(block, ["settings" | known]), settings, fn {key, value}, result ->
      if Map.has_key?(result, key) and result[key] != value,
        do: throw(:publication_setting_conflict)

      Map.put(result, key, value)
    end)
  end

  defp grading!(question) do
    props = question["props"]

    case props["settings"]["answer_key"] do
      nil ->
        :ok

      key when is_map(key) ->
        if not is_nil(key["points"]) and not is_nil(props["points"]) and
             key["points"] != props["points"], do: throw(:publication_grade_points)

        if props["type"] in ~w(multiple_choice checkboxes) do
          correct =
            tl(question["content"])
            |> Enum.filter(& &1["props"]["correct"])
            |> Enum.map(& &1["props"]["id"])

          expected =
            if props["type"] == "multiple_choice",
              do: if(length(correct) == 1, do: hd(correct), else: nil),
              else: Enum.sort(correct)

          actual =
            if is_list(key["correct_answer"]),
              do: Enum.sort(key["correct_answer"]),
              else: key["correct_answer"]

          unless actual == expected, do: throw(:publication_grade_answer)
        end

      _ ->
        throw(:publication_grade_shape)
    end
  end

  defp semantic(value) when is_list(value), do: Enum.map(value, &semantic/1)

  defp semantic(value) when is_map(value) do
    value =
      if is_binary(value["type"]) and is_binary(value["id"]) and
           Regex.match?(~r/^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$/, value["id"]),
         do: Map.delete(value, "id"),
         else: value

    Map.new(value, fn {key, item} -> {key, semantic(item)} end)
  end

  defp semantic(value), do: value

  defp merge_settings(saved, source, path) do
    Enum.reduce(source, {saved, []}, fn {key, value}, {out, changes} ->
      cond do
        not Map.has_key?(out, key) ->
          {Map.put(out, key, value),
           changes ++
             [%{"path" => path ++ [key], "operation" => "recover_retained_source_setting"}]}

        is_map(value) and is_map(out[key]) ->
          {merged, nested} = merge_settings(out[key], value, path ++ [key])
          {Map.put(out, key, merged), changes ++ nested}

        out[key] == value ->
          {out, changes}

        true ->
          throw(:publication_retained_setting_conflict)
      end
    end)
  end

  defp reconcile(result, source, namespace) do
    case RelayMark.DocumentSource.import_source(source,
           namespace: namespace <> ":retained-publication-source"
         ) do
      {:ok, %{document: document, identity_mapping: mapping}} ->
        saved = Enum.filter(result.document["blocks"], &(&1["type"] == "relay.form_question"))
        retained = Enum.filter(document["blocks"], &(&1["type"] == "relay.form_question"))

        prose = fn doc ->
          Enum.reject(doc["blocks"], &(&1["type"] == "relay.form_question")) |> semantic()
        end

        unless length(saved) == length(retained) and prose.(result.document) == prose.(document),
          do: throw(:publication_retained_prose_conflict)

        {questions, changes} =
          Enum.zip(saved, retained)
          |> Enum.map_reduce([], fn {saved, q}, changes ->
            unless saved["props"]["id"] == q["props"]["id"] and
                     saved["props"]["type"] == q["props"]["type"] and
                     length(saved["content"]) == length(q["content"]) and
                     semantic(hd(saved["content"])) == semantic(hd(q["content"])),
                   do: throw(:publication_retained_question_conflict)

            {choices, option_changes} =
              Enum.zip(tl(saved["content"]), tl(q["content"]))
              |> Enum.map_reduce([], fn {old, option}, changes ->
                unless old["props"]["id"] == option["props"]["id"] and
                         old["props"]["correct"] == option["props"]["correct"] and
                         old["content"] == option["content"],
                       do: throw(:publication_retained_option_conflict)

                if not is_nil(old["props"]["points"]) and
                     old["props"]["points"] != option["props"]["points"],
                   do: throw(:publication_retained_option_points)

                {settings, extra} =
                  merge_settings(old["props"]["settings"], option["props"]["settings"], [
                    "question",
                    q["props"]["id"],
                    "option",
                    option["props"]["id"],
                    "settings"
                  ])

                {put_in(option, ["props", "settings"], settings), changes ++ extra}
              end)

            q = Map.put(q, "content", [hd(q["content"]) | choices])

            {props, recovered} =
              Enum.reduce(~w(required points min max), {q["props"], []}, fn key,
                                                                            {props, recovered} ->
                cond do
                  is_nil(saved["props"][key]) and not is_nil(props[key]) ->
                    {props,
                     recovered ++
                       [
                         %{
                           "path" => ["question", props["id"], key],
                           "operation" => "recover_retained_source_setting"
                         }
                       ]}

                  saved["props"][key] == props[key] ->
                    {props, recovered}

                  true ->
                    throw(:publication_retained_core_conflict)
                end
              end)

            {settings, extra} =
              merge_settings(saved["props"]["settings"], props["settings"], [
                "question",
                props["id"],
                "settings"
              ])

            q = Map.put(q, "props", Map.put(props, "settings", settings))
            grading!(q)
            {q, changes ++ option_changes ++ recovered ++ extra}
          end)

        questions = Map.new(questions, &{&1["props"]["id"], &1})

        document =
          Map.update!(
            document,
            "blocks",
            &Enum.map(&1, fn block ->
              if block["type"] == "relay.form_question",
                do: questions[block["props"]["id"]],
                else: block
            end)
          )

        with {:ok, document} <- RelayMark.DocumentXML.normalize_document(document),
             do:
               {:ok,
                %{
                  document: document,
                  identity_mapping: mapping,
                  normalizations:
                    result.normalizations ++
                      changes ++
                      [%{"path" => [], "operation" => "use_retained_publication_source"}]
                }}

      {:error, diagnostics} ->
        {:error, diagnostics}
    end
  end

  defp error(reason),
    do:
      {:error,
       [
         %{
           "level" => "error",
           "code" => "relaymark.form_publication_import.invalid",
           "reason" => inspect(reason)
         }
       ]}
end
