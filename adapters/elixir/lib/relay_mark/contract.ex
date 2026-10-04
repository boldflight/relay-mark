defmodule RelayMark.Contract do
  @moduledoc "The single canonical editor and sync compatibility contract."
  @path Path.expand("../../priv/relaymark/contract.json", __DIR__)
  @external_resource @path
  @contract @path |> File.read!() |> Jason.decode!()
  def version, do: @contract["contract_version"]
  def schema, do: @contract["schema"]
  def source_contract, do: @contract["source_contract"]
  def descriptor, do: @contract
end
