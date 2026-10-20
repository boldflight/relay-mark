defmodule RelayMark.PaperControl do
  @moduledoc "Bounded authored Paper control contract; host interactions stay outside the AST."

  @doc "The canonical one-line source of `%{\"control\" => ..., fields...}`."
  def canonical_source(%{"control" => _} = props) do
    case RelayMark.Engine.text("paper_control_source", props) do
      {:ok, source} -> {:ok, source}
      {:error, _} -> :error
    end
  end

  def canonical_source(_), do: :error

  @doc "Whether an authored control block's source agrees with its fields."
  def valid_block?(%{"props" => props, "content" => []}) do
    with source when is_binary(source) <- props["source"],
         {:ok, ^source} <- canonical_source(Map.delete(props, "source")) do
      true
    else
      _ -> false
    end
  end

  def valid_block?(_), do: false
end
