defmodule RelayMark.Link do
  @moduledoc "Portable inert authored navigation; hosts authorize internal destinations."
  def safe_href?(value) when is_binary(value) do
    cond do
      value == "" or Regex.match?(~r/[\s\x00-\x1f\x7f<>\\]/u, value) ->
        false

      String.starts_with?(value, "#") ->
        String.length(value) > 1

      String.starts_with?(value, "/") ->
        not String.starts_with?(value, "//")

      Regex.match?(~r/^https?:\/\//i, value) ->
        uri = URI.parse(value)

        uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
          is_nil(uri.userinfo)

      Regex.match?(
        ~r/^relay:(?:entity|note|file|tag)\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
        value
      ) ->
        true

      Regex.match?(~r/^mailto:/i, value) ->
        value |> String.slice(7..-1//1) |> String.split("?") |> hd() != ""

      Regex.match?(~r/^tel:/i, value) ->
        Regex.match?(~r/^[+0-9().-]+$/, String.slice(value, 4..-1//1))

      true ->
        false
    end
  end

  def safe_href?(_), do: false

  def safe_image_source?(value) when is_binary(value) do
    safe_href?(value) and String.length(value) <= 2048 and
      cond do
        String.starts_with?(value, "/") ->
          value
          |> String.split(["?", "#"])
          |> hd()
          |> String.split("/")
          |> Enum.all?(fn segment -> URI.decode(segment) not in [".", ".."] end)

        Regex.match?(~r/^https:\/\//i, value) ->
          URI.parse(value).scheme == "https"

        true ->
          false
      end
  end

  def safe_image_source?(_), do: false
end
