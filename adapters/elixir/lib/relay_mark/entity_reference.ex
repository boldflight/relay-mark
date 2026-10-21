defmodule RelayMark.EntityReference do
  @moduledoc "Bounded authored block entity reference source."

  @doc "The parts of a strict `@EntityRef(...)` source, or `:error`."
  def parse_source(source) when is_binary(source) do
    case RelayMark.Engine.source("parse_entity_reference", source) do
      {:ok, %{} = parsed} -> {:ok, parsed}
      _ -> :error
    end
  end

  def parse_source(_), do: :error
end
