defmodule RelayMark.Contract do
  @moduledoc "The single canonical editor and sync compatibility contract."
  @path Path.expand("../../priv/relaymark/contract.json", __DIR__)
  @external_resource @path
  @contract @path |> File.read!() |> Jason.decode!()
  def version, do: @contract["contract_version"]
  def schema, do: @contract["schema"]
  def source_contract, do: @contract["source_contract"]
  def descriptor, do: @contract

  @doc """
  Admits a stored or received document descriptor only when it is exactly this
  engine's contract (version, schema, source contract and physical schema
  hash). Any other descriptor, such as the hashless one of a document that
  still holds aggregate question settings, is refused so the host recovers
  through its existing path instead of reading it.
  """
  def admit(descriptor),
    do:
      RelayMark.Engine.json("admit_descriptor", descriptor)
      |> RelayMark.keyed_error("relaymark.contract.unsupported_descriptor")
end
