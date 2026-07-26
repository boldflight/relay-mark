defmodule RelayMark.JSON do
  @moduledoc false

  @spec decode(binary()) :: {:ok, term()} | {:error, term()}
  def decode(json) when is_binary(json), do: Jason.decode(json)
end
