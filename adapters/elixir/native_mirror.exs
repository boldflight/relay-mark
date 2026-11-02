# The one owner of native/relaymark: the RelayMark engine source the Hex package
# ships and the NIF compiles. It is rebuilt from scratch every time, never patched
# in place, because a stale copy once shipped as relay_mark_elixir 0.7.5 without
# three engine modules (input_rules, settings_rebase, task_drafts) that lib.rs
# declared, so the published NIF failed to compile everywhere.
#
# Copies crates/relaymark-core (Cargo.toml and src) and every file its sources
# include with include_str!/include_bytes!, then fails loudly if any `mod`
# declaration has no file. Evaluated by lib/relay_mark/native.ex while compiling
# inside the repository, and by the hex.build/hex.publish aliases in mix.exs.
# Evaluating it returns the function; it defines no module.

fn repository, mirror ->
  core = "crates/relaymark-core"

  unless File.dir?(Path.join(repository, core)) do
    raise "relaymark-core not found under #{repository}"
  end

  File.rm_rf!(mirror)

  copy = fn relative ->
    source = Path.join(repository, relative)
    unless File.exists?(source), do: raise("native mirror: #{relative} does not exist")
    target = Path.join(mirror, relative)
    File.mkdir_p!(Path.dirname(target))
    File.cp_r!(source, target)
  end

  copy.(Path.join(core, "Cargo.toml"))
  copy.(Path.join(core, "src"))

  sources = Path.wildcard(Path.join([mirror, core, "src", "**", "*.rs"]))

  # Every file a source includes, resolved against the source's place in the repository.
  includes =
    for file <- sources,
        [_, path] <- Regex.scan(~r/include_(?:str|bytes)!\(\s*"([^"]+)"\s*\)/, File.read!(file)),
        uniq: true do
      in_repository = Path.join(repository, Path.relative_to(file, mirror))
      Path.relative_to(Path.expand(path, Path.dirname(in_repository)), repository)
    end

  Enum.each(includes, fn relative ->
    unless File.exists?(Path.join(mirror, relative)), do: copy.(relative)
  end)

  # A `mod name;` needs name.rs or name/mod.rs beside it (lib.rs and mod.rs declare
  # their own directory's modules; any other file declares modules in a directory
  # named after itself).
  missing =
    for file <- sources,
        [_, name] <-
          Regex.scan(
            ~r/^\s*(?:pub(?:\([^)]*\))?\s+)?mod\s+([a-z_][a-z0-9_]*)\s*;/m,
            File.read!(file)
          ),
        base =
          if(Path.basename(file) in ["lib.rs", "mod.rs"],
            do: Path.dirname(file),
            else: Path.rootname(file)
          ),
        not File.exists?(Path.join(base, name <> ".rs")),
        not File.exists?(Path.join([base, name, "mod.rs"])),
        do: "#{Path.relative_to(file, mirror)}: mod #{name}"

  if missing != [] do
    raise "native mirror is incomplete; declared modules without files:\n  " <>
            Enum.join(missing, "\n  ")
  end

  mirror
end
