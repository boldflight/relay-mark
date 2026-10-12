defmodule RelayMark.CanonicalJSON do
  @moduledoc "Deterministic JSON bytes shared by portable projections and host digest contracts."

  @spec encode(term()) :: binary()
  def encode(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, nested} -> {to_string(key), nested} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(",", fn {key, nested} ->
        Jason.encode!(key) <> ":" <> encode(nested)
      end)

    "{" <> entries <> "}"
  end

  def encode(value) when is_list(value), do: "[" <> Enum.map_join(value, ",", &encode/1) <> "]"
  # Use the runtime's shortest round-trip decimal digits, with ECMAScript's
  # fixed/exponent placement (RFC 8785 section 3.2.2.3). Key ordering stays the
  # existing UTF-8 wire contract. Never round geometry or rewrite receipts.
  def encode(value) when is_float(value) and value == 0.0, do: "0"

  def encode(value) when is_float(value) do
    sign = if value < 0, do: "-", else: ""
    raw = :erlang.float_to_binary(abs(value), [:short])
    [mantissa | exponent] = String.split(raw, "e")

    power =
      case exponent do
        [] -> 0
        [encoded] -> String.to_integer(encoded)
      end

    [whole, fraction] = String.split(mantissa, ".")
    raw_digits = whole <> fraction
    leading = byte_size(raw_digits) - byte_size(String.trim_leading(raw_digits, "0"))
    digits = raw_digits |> String.trim_leading("0") |> String.trim_trailing("0")
    position = byte_size(whole) + power - leading
    length = byte_size(digits)

    body =
      cond do
        position > 0 and position <= 21 and length <= position ->
          digits <> String.duplicate("0", position - length)

        position > 0 and position <= 21 ->
          binary_part(digits, 0, position) <>
            "." <> binary_part(digits, position, length - position)

        position <= 0 and position > -6 ->
          "0." <> String.duplicate("0", -position) <> digits

        true ->
          <<first::binary-size(1), tail::binary>> = digits
          coefficient = first <> if(tail == "", do: "", else: "." <> tail)
          exponent = position - 1

          coefficient <>
            "e" <> if(exponent >= 0, do: "+", else: "") <> Integer.to_string(exponent)
      end

    sign <> body
  end

  def encode(value), do: Jason.encode!(value)
end
