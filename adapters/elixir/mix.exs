defmodule RelayMarkElixir.MixProject do
  use Mix.Project

  @version "0.7.0"
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
      {:jsv, ">= 0.22.0"},
      {:jason, "~> 1.4"},
      {:mdex, "~> 0.13.5"},
      {:quicksand, "0.1.1"},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "relay_mark_elixir",
      licenses: ["MIT"],
      links: %{"Source" => @source_url},
      files: [
        "lib",
        "priv",
        ".formatter.exs",
        "mix.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "elixir-#{@version}"
    ]
  end
end
