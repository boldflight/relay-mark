defmodule RelayMark.Native do
  @moduledoc false
  # The RelayMark engine (crates/relaymark-core) as a NIF, compiled from source.
  # A Hex package ships the copy in native/relaymark.

  repository = Path.expand("../../../..", __DIR__)
  mirror = Path.expand("../../native/relaymark", __DIR__)

  # Inside the relay-mark repository the engine is copied fresh into native/relaymark
  # by native_mirror.exs, the one owner of that copy (see it for why). Directories
  # are external resources too, so adding or removing an engine file recompiles this.
  if File.dir?(Path.join(repository, "crates/relaymark-core")) do
    {sync, _binding} = Code.eval_file(Path.expand("../../native_mirror.exs", __DIR__))
    sync.(repository, mirror)

    for directory <- ["crates/relaymark-core/src", "spec/relaymark"],
        path <- [
          Path.join(repository, directory)
          | Path.wildcard(Path.join([repository, directory, "**", "*"]))
        ],
        do: @external_resource(path)
  end

  use Rustler, otp_app: :relay_mark_elixir, crate: "relay_mark_nif", mode: :release

  def run(_job, _input, _options), do: :erlang.nif_error(:nif_not_loaded)
  def run_dirty(_job, _input, _options), do: :erlang.nif_error(:nif_not_loaded)
end
