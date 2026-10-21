defmodule RelayMark.Native do
  @moduledoc false
  # The RelayMark engine (crates/relaymark-core) as a NIF, compiled from source.
  # Inside the relay-mark repository the engine and the spec files it compiles
  # in are copied to native/relaymark first; a Hex package ships that copy.

  repository = Path.expand("../../../..", __DIR__)
  mirror = Path.expand("../../native/relaymark", __DIR__)

  # The engine's sources and the spec files it compiles in, nothing else.
  copied = [
    "crates/relaymark-core/Cargo.toml",
    "crates/relaymark-core/src",
    "spec/relaymark/contract.json",
    "spec/relaymark/editor-schema.json",
    "spec/relaymark/xml-attribute-encoding.json",
    "spec/relaymark/directives",
    "spec/relaymark/schemas"
  ]

  if File.dir?(Path.join(repository, "crates/relaymark-core")) do
    File.rm_rf!(mirror)

    for relative <- copied do
      target = Path.join(mirror, relative)
      File.mkdir_p!(Path.dirname(target))
      File.cp_r!(Path.join(repository, relative), target)
    end

    for directory <- ["crates/relaymark-core/src", "spec/relaymark"],
        path <- Path.wildcard(Path.join([repository, directory, "**", "*"])),
        do: @external_resource(path)
  end

  use Rustler, otp_app: :relay_mark_elixir, crate: "relay_mark_nif", mode: :release

  def run(_job, _input, _options), do: :erlang.nif_error(:nif_not_loaded)
  def run_dirty(_job, _input, _options), do: :erlang.nif_error(:nif_not_loaded)
end
