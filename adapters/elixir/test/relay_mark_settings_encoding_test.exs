defmodule RelayMark.SettingsEncodingTest do
  use ExUnit.Case, async: true

  defp document do
    %{
      "type" => "relaymark.document",
      "blocks" => [
        %{
          "type" => "relay.form_question",
          "id" => "b00000000000140008000000000000000",
          "props" => %{
            "id" => "recording",
            "type" => "video_response",
            "required" => false,
            "points" => nil,
            "min" => nil,
            "max" => nil,
            "settings" => %{
              "max_duration" => 60,
              "audio_only" => false,
              "nullable" => nil,
              "🌍" => %{"nested" => true},
              "" => 0
            }
          },
          "content" => [
            %{
              "type" => "paragraph",
              "id" => "b00000000000240008000000000000000",
              "content" => [
                %{"type" => "strong", "content" => [%{"type" => "text", "text" => "Explain 🌍"}]}
              ]
            }
          ]
        }
      ]
    }
  end

  test "question settings are one aggregate attribute and per-key state is refused" do
    expected = document()
    settings = hd(expected["blocks"])["props"]["settings"]
    assert {:ok, snapshot} = RelayMark.DocumentXML.from_document(expected)
    attrs = hd(snapshot["children"])["attributes"]
    assert attrs["settings"] == settings
    refute Enum.any?(Map.keys(attrs), &String.starts_with?(&1, "settings:"))
    assert {:ok, ^expected} = RelayMark.DocumentXML.to_document(snapshot)

    for bad <- [
          %{"settings" => true, "settings:bWF4X2R1cmF0aW9u" => 60},
          %{"settings" => %{"a" => 1}, "settings:eA" => true},
          %{"settings" => true},
          %{"settings:eA" => 1}
        ] do
      malformed =
        put_in(
          snapshot,
          ["children", Access.at(0), "attributes"],
          Map.merge(Map.delete(attrs, "settings"), bad)
        )

      assert {:error, _} = RelayMark.DocumentXML.to_document(malformed)
    end
  end
end
