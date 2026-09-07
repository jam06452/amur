defmodule Amur.MixProject do
  use Mix.Project

  def project do
    [
      app: :amur,
      version: "0.3.3",
      elixir: "~> 1.15",
      description: "Simple OAuth for Plug apps",
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      assets: %{"assets" => "assets"},
      groups_for_modules: [
        Providers: [
          ~r/^Amur\.Providers(\.|$)/
        ]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:assent, "~> 0.3"},
      {:plug, ">= 0.0.0"},
      {:igniter, "~> 0.8", optional: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:mix_audit, "~> 2.1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/jam06452/amur"}
    ]
  end
end
