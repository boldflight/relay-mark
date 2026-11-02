defmodule RelayMarkElixir.MixProject do
  use Mix.Project

  @version "0.7.6"
  @source_url "https://github.com/boldflight/relay-mark"

  def project do
    [
      app: :relay_mark_elixir,
      version: @version,
      aliases: aliases(),
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description:
        "Generic Elixir models and portable validation for RelayMark documents and manifests",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :logger]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:rustler, "~> 0.37.1", runtime: false},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "relay_mark_elixir",
      licenses: ["MIT", "Apache-2.0"],
      links: %{"Source" => @source_url},
      files: [
        "lib",
        "priv/collaboration",
        "priv/relaymark",
        "native/relay_mark_nif/Cargo.toml",
        "native/relay_mark_nif/Cargo.lock",
        "native/relay_mark_nif/src",
        "native/relaymark",
        ".formatter.exs",
        "mix.exs",
        "README.md",
        "LICENSE-MIT",
        "LICENSE-APACHE",
        "THIRD_PARTY_NOTICES.md",
        "CHANGELOG.md"
      ]
    ]
  end

  # Release gate (docs/engineering/release.md): docs must build with
  # `MIX_ENV=dev mix docs --warnings-as-errors` and the unpacked package must
  # compile as a dependency (scripts/check-elixir-package.sh) before any publish.
  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE-MIT",
        "LICENSE-APACHE",
        "THIRD_PARTY_NOTICES.md"
      ],
      source_ref: "elixir-#{@version}"
    ]
  end

  # Building or publishing the package always ships a fresh, complete copy of the
  # engine (native_mirror.exs), never whatever an earlier compile left behind.
  defp aliases do
    [
      "hex.build": [&sync_native_mirror/1, "hex.build"],
      "hex.publish": [&sync_native_mirror/1, "hex.publish"]
    ]
  end

  defp sync_native_mirror(_args) do
    repository = Path.expand("../..", __DIR__)

    unless File.dir?(Path.join(repository, "crates/relaymark-core")) do
      Mix.raise("hex.build and hex.publish run only inside the relay-mark repository")
    end

    {sync, _binding} = Code.eval_file(Path.join(__DIR__, "native_mirror.exs"))
    sync.(repository, Path.join(__DIR__, "native/relaymark"))
  end
end
