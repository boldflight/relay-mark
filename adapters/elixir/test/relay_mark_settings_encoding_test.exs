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

  test "current question settings have independent physical fields without changing authored identity or null presence" do
    expected = document()
    assert {:ok, snapshot} = RelayMark.DocumentXML.from_document(expected)
    attrs = hd(snapshot["children"])["attributes"]
    assert attrs["settings"] == true
    assert attrs["settings:bWF4X2R1cmF0aW9u"] == 60
    assert Map.has_key?(attrs, "settings:bnVsbGFibGU")
    assert attrs["settings:bnVsbGFibGU"] == nil
    assert attrs["settings:"] == 0
    assert {:ok, ^expected} = RelayMark.DocumentXML.to_document(snapshot)

    for bad <- [
          %{"settings" => %{}},
          %{"settings" => false},
          %{"settings" => true, "settings:eA=" => 1},
          %{"settings" => true, "settings:_w" => 1}
        ] do
      malformed =
        put_in(
          snapshot,
          ["children", Access.at(0), "attributes"],
          Map.merge(
            attrs |> Map.reject(fn {key, _} -> String.starts_with?(key, "settings") end),
            bad
          )
        )

      assert {:error, _} = RelayMark.DocumentXML.to_document(malformed)
    end
  end

  test "finite aggregate conversion plans exact field changes and explicitly requires a physical history cut" do
    expected = document()
    assert {:ok, current} = RelayMark.DocumentXML.from_document(expected)
    attrs = hd(current["children"])["attributes"]
    settings = hd(expected["blocks"])["props"]["settings"]

    old_attrs =
      attrs
      |> Map.reject(fn {key, _} -> String.starts_with?(key, "settings:") end)
      |> Map.put("settings", settings)

    old = put_in(current, ["children", Access.at(0), "attributes"], old_attrs)
    assert {:error, _} = RelayMark.DocumentXML.to_document(old)
    assert {:ok, converted} = RelayMark.DocumentXML.import_aggregate_settings_snapshot(old)
    assert converted["snapshot"] == current
    assert converted["document"] == expected
    assert converted["requires_physical_history_cut"] == true

    assert hd(converted["normalizations"]) == %{
             "path" => [0],
             "operation" => "set_attribute",
             "name" => "settings",
             "before" => settings,
             "value" => true
           }

    assert hd(old["children"])["attributes"] == old_attrs

    assert {:ok, already_current} =
             RelayMark.DocumentXML.import_aggregate_settings_snapshot(current)

    assert already_current["snapshot"] == current
    assert already_current["document"] == expected
    assert already_current["normalizations"] == []
    assert already_current["requires_physical_history_cut"] == false
    mixed = put_in(old, ["children", Access.at(0), "attributes", "settings:eA"], 1)
    assert {:error, _} = RelayMark.DocumentXML.import_aggregate_settings_snapshot(mixed)

    # The first block can be converted, but a later invalid or mixed block must
    # return only an error, never a partially prepared snapshot or change list.
    for second <- [hd(current["children"]), hd(mixed["children"])] do
      input = Map.put(old, "children", [hd(old["children"]), second])

      assert {:error, [%{"code" => "relaymark.document_xml.invalid"}]} =
               RelayMark.DocumentXML.import_aggregate_settings_snapshot(input)
    end

    assert hd(old["children"])["attributes"] == old_attrs
  end
end
