defmodule RelayMark.Diagnostic do
  @moduledoc """
  A portable RelayMark validation diagnostic.

  Diagnostics use JSON string keys so they can be compared directly with the
  canonical conformance fixtures and serialized without adapter-specific
  conversion.
  """

  @type level :: String.t()
  @type t :: %{required(String.t()) => term()}

  @optional_fields [:location, :suggestion, :path, :meta]

  @spec error(String.t(), String.t(), keyword()) :: t()
  def error(code, message, options \\ []) when is_binary(code) and is_binary(message) do
    Enum.reduce(
      @optional_fields,
      %{"level" => "error", "code" => code, "message" => message},
      fn field, diagnostic ->
        case Keyword.fetch(options, field) do
          {:ok, nil} -> diagnostic
          {:ok, value} -> Map.put(diagnostic, Atom.to_string(field), value)
          :error -> diagnostic
        end
      end
    )
  end
end
