defmodule Amur.MixProject do
  use Mix.Project

  def project do
    [
      app: :amur,
      version: "0.3.4",
      elixir: "~> 1.15",
      description:
        "OAuth 2.0 and OAuth 1.0 authentication for Elixir Plug and Phoenix applications, with PKCE, state protection, and 24 providers.",
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:mix]],
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
      source_url: "https://github.com/jam06452/amur",
      homepage_url: "https://hex.pm/packages/amur",
      canonical: "https://hexdocs.pm/amur",
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

  defp aliases do
    [
      ci: ["credo --strict", "format --check-formatted", "deps.audit", "dialyzer"]
    ]
  end

  defp deps do
    [
      {:assent, "~> 0.3"},
      {:plug, ">= 0.0.0"},
      {:igniter, "~> 0.8.4", optional: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:mix_audit, "~> 2.1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/jam06452/amur",
        "HexDocs" => "https://hexdocs.pm/amur",
        "Hex" => "https://hex.pm/packages/amur"
      }
    ]
  end
end
