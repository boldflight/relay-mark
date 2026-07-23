defmodule RelayMarkElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :relay_mark_elixir,
      version: "0.3.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:exonerate, "~> 1.2", runtime: false},
      {:jason, "~> 1.4", runtime: false}
    ]
  end
end
