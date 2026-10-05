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

  @schema_path Path.expand("../../priv/relaymark/editor-schema.json", __DIR__)
  @external_resource @schema_path
  @defaults @schema_path
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("marks")
            |> Enum.find(&(&1["name"] == "link"))
            |> Map.fetch!("attrs")
            |> Map.delete("href")
            |> Map.new(fn {key, spec} -> {key, spec["default"]} end)
  def attributes(href, props \\ %{})

  def attributes(href, props) when is_map(props) do
    attrs = Map.merge(Map.put(@defaults, "href", href), props)

    if Enum.all?(Map.keys(props), &Map.has_key?(@defaults, &1)) and safe_attributes?(attrs),
      do: {:ok, attrs},
      else: {:error, :link_attributes}
  end

  def attributes(_, _), do: {:error, :link_attributes}

  def safe_attributes?(attrs) when is_map(attrs) do
    Enum.sort(Map.keys(attrs)) == Enum.sort(["href" | Map.keys(@defaults)]) and
      safe_href?(attrs["href"]) and
      safe_target?(attrs["target"]) and
      Enum.all?(
        ~w(rel class title),
        &nullable_text?(attrs[&1], ~r/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/u)
      )
  end

  def safe_attributes?(_), do: false

  def properties(attrs),
    do:
      Map.reject(Map.take(attrs, Map.keys(@defaults)), fn {key, value} ->
        value == @defaults[key]
      end)

  def rendered_attributes(attrs) do
    if if(is_binary(attrs["target"]), do: String.downcase(attrs["target"]), else: nil) not in [
         nil,
         "",
         "_self",
         "_parent",
         "_top"
       ] do
      tokens = String.split(attrs["rel"] || "")

      tokens =
        Enum.reduce(~w(noopener noreferrer), tokens, fn token, list ->
          if Enum.any?(list, &(String.downcase(&1) == token)), do: list, else: list ++ [token]
        end)

      Map.put(attrs, "rel", Enum.join(tokens, " "))
    else
      attrs
    end
  end

  defp safe_target?(nil), do: true

  defp safe_target?(value) when is_binary(value) do
    nullable_text?(value, ~r/[\x00-\x1f\x7f]/u) and
      (not String.starts_with?(value, "_") or
         String.downcase(value) in ~w(_blank _self _parent _top))
  end

  defp safe_target?(_), do: false
  defp nullable_text?(nil, _), do: true
  defp nullable_text?(value, regex), do: is_binary(value) and not Regex.match?(regex, value)

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
