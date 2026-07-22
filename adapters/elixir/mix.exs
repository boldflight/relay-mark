defmodule RelayMarkElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :relay_mark_elixir,
      version: "0.3.0-draft",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end
end
