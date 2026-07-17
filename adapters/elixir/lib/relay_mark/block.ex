defmodule RelayMark.Block do
  @moduledoc "RelayMark block struct and helpers."

  alias RelayMark.Inline

  defstruct id: nil,
            type: nil,
            props: %{},
            content: [],
            evidence_refs: []

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          props: map(),
          content: [t() | Inline.t()],
          evidence_refs: [String.t()]
        }

  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      id: Map.fetch!(map, "id"),
      type: Map.fetch!(map, "type"),
      props: Map.get(map, "props", %{}),
      content: Enum.map(Map.get(map, "content", []), &content_from_map/1),
      evidence_refs: Map.get(map, "evidence_refs", [])
    }
  end

  @spec plain_text(t() | Inline.t()) :: String.t()
  def plain_text(%__MODULE__{content: content}) do
    content
    |> Enum.map(&plain_text/1)
    |> Enum.join()
  end

  def plain_text(%Inline{text: text}) when is_binary(text), do: text
  def plain_text(%Inline{type: "relay." <> _, label: label}) when is_binary(label), do: label

  def plain_text(%Inline{content: content}) do
    content
    |> Enum.map(&plain_text/1)
    |> Enum.join()
  end

  defp content_from_map(%{"type" => type} = map) do
    if Inline.inline_type?(type) do
      Inline.from_map(map)
    else
      from_map(map)
    end
  end
end
