defmodule RelayMark.InlineAtoms do
  @moduledoc "Canonical inline reference source. Resolution remains host-owned."

  @doc "The canonical `[[Type: id | label]]` source of an inline entity reference."
  def reference_source(type, id, label)
      when is_binary(type) and is_binary(id) and is_binary(label) do
    case RelayMark.Engine.call("entity_reference_source", "", %{
           "type" => type,
           "id" => id,
           "label" => label
         }) do
      {:ok, source} -> {:ok, source}
      {:error, _} -> :error
    end
  end

  def reference_source(_, _, _), do: :error
end
