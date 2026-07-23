defmodule RelayMark.ValidationError do
  @moduledoc """
  Raised when `RelayMark.validate_document!/1` receives an invalid document.
  """

  defexception [:message, diagnostics: []]

  @impl Exception
  def exception(options) do
    diagnostics = Keyword.fetch!(options, :diagnostics)
    count = length(diagnostics)

    %__MODULE__{
      diagnostics: diagnostics,
      message: "RelayMark document validation failed with #{count} diagnostic(s)."
    }
  end
end
