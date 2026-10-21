defmodule RelayMarkElixir.MixProject do
  use Mix.Project

  @version "0.7.4"
  @source_url "https://github.com/boldflight/relay-mark"

  def project do
    [
      app: :relay_mark_elixir,
      version: @version,
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
end
