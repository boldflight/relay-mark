defmodule RelayMark.Resource do
  @moduledoc "RelayMark resource struct."

  defstruct id: nil,
            type: nil,
            uri: nil,
            label: nil,
            scope: nil,
            props: %{}

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          uri: String.t() | nil,
          label: String.t() | nil,
          scope: String.t() | nil,
          props: map()
        }

  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      id: Map.fetch!(map, "id"),
      type: Map.fetch!(map, "type"),
      uri: Map.get(map, "uri"),
      label: Map.get(map, "label"),
      scope: Map.get(map, "scope"),
      props: Map.get(map, "props", %{})
    }
  end

  @spec scripture_release(t()) :: {:ok, RelayMark.Scripture.Release.t()} | :error
  def scripture_release(%__MODULE__{type: "scripture", props: props}) do
    {:ok, RelayMark.Scripture.Release.from_map(props)}
  end

  def scripture_release(%__MODULE__{}), do: :error
end
