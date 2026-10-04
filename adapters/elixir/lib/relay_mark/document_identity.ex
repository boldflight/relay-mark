defmodule RelayMark.DocumentIdentity do
  @moduledoc "Deterministic stable-once identity allocation for canonical source and finite migration."
  def generate(namespace, path) when is_binary(namespace) and is_list(path) do
    hash =
      :crypto.hash(:sha256, namespace <> "\0" <> Enum.join(path, "."))
      |> Base.encode16(case: :lower)

    "b" <>
      binary_part(hash, 0, 12) <>
      "4" <> binary_part(hash, 13, 3) <> "8" <> binary_part(hash, 17, 15)
  end
end
