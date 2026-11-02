#!/bin/sh
# Release gate for relay_mark_elixir (docs/engineering/release.md). Run it from a
# clean state before anyone is asked to publish, and CI runs it on every push:
#
#   scripts/check-elixir-package.sh
#
# 1. Starts clean: no native/relaymark mirror, _build, deps or doc.
# 2. Docs build with zero warnings (MIX_ENV=dev mix docs --warnings-as-errors).
# 3. Builds the package (the hex.build alias rebuilds the engine mirror) and
#    unpacks it.
# 4. Compiles that unpacked package as a path dependency of a scratch Mix project
#    and calls the engine, so a package missing engine source fails here, not on
#    Hex. 0.7.5 shipped without three engine modules; this is the check that would
#    have caught it.
set -eu

repository=$(cd "$(dirname "$0")/.." && pwd)
adapter="$repository/adapters/elixir"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/relay-mark-package-gate.XXXXXX")
trap 'rm -rf "$scratch"' EXIT INT TERM

# The committed package files (priv/collaboration, priv/relaymark) must equal a fresh build.
if command -v npm >/dev/null 2>&1 && [ -d "$repository/node_modules" ]; then
  (cd "$repository" && npm run --silent build:collaboration &&
    changed=$(git status --porcelain -- adapters/elixir/priv src adapters/swift/Sources/RelayMarkModel/PMSchema.swift) &&
    if [ -n "$changed" ]; then echo "Packaged files differ from a fresh build:" >&2; echo "$changed" >&2; exit 1; fi)
else
  echo "note: node_modules missing; skipping the packaged-files freshness check (CI runs it)"
fi

cd "$adapter"
rm -rf native/relaymark _build deps doc

mix deps.get --check-locked
MIX_ENV=dev mix docs --warnings-as-errors

version=$(mix run --no-compile --no-start -e 'IO.write(Mix.Project.config()[:version])' 2>/dev/null || true)
mix hex.build --unpack --output "$scratch/package"

mkdir -p "$scratch/consumer/lib"
cat >"$scratch/consumer/mix.exs" <<EOF
defmodule PackageGate.MixProject do
  use Mix.Project

  def project do
    [app: :package_gate, version: "0.0.0", deps: [{:relay_mark_elixir, path: "$scratch/package"}]]
  end
end
EOF

cd "$scratch/consumer"
mix deps.get
mix compile --warnings-as-errors
mix run -e '
  {:ok, admitted} = RelayMark.Contract.admit(RelayMark.Contract.descriptor())
  IO.puts("relay_mark_elixir package compiles and runs the engine: " <> inspect(admitted["schema_hash"]))
'

echo "relay_mark_elixir ${version:-package} passed the release gate"
