defmodule RelayMarkElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :relay_mark_elixir,
      version: "0.5.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
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
      {:jsv, "~> 0.21.2"},
      {:jason, "~> 1.4"}
    ]
  end
end
