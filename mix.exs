defmodule Amur.MixProject do
  use Mix.Project

  def project do
    [
      app: :amur,
      version: "0.1.0",
      elixir: "~> 1.15",
      description: "Simple OAuth for Plug apps",
      deps: deps(),
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:assent, "~> 0.2"},
      {:plug, "~> 1.14"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/jam06452/amur"}
    ]
  end
end
