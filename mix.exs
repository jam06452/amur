defmodule Amur.MixProject do
  use Mix.Project

  @version "0.3.4"
  @source_url "https://github.com/jam06452/amur"

  def project do
    [
      app: :amur,
      version: @version,
      elixir: "~> 1.15",
      description:
        "OAuth 2.0 and OAuth 1.0 authentication for Elixir Plug and Phoenix applications, with PKCE, state protection, and 24 providers.",
      aliases: aliases(),
      cli: cli(),
      dialyzer: [plt_add_apps: [:mix]],
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  def cli do
    [preferred_envs: [{:"test.coverage", :test}, ci: :test, test: :test]]
  end

  defp docs do
    [
      main: "overview",
      assets: %{"assets" => "assets"},
      source_url: @source_url,
      source_ref: "v#{@version}",
      homepage_url: "https://hex.pm/packages/amur",
      canonical: "https://hexdocs.pm/amur",
      extra_section: "GUIDES",
      api_reference: false,
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules()
    ]
  end

  defp extras do
    [
      # Introduction
      "guides/overview.md",
      "guides/introduction/installation.md",

      # Learning
      "guides/learning/providers.md",
      "guides/learning/configuration.md",
      "guides/learning/oauth_flow.md",
      "guides/learning/custom_providers.md",
      "guides/learning/sign_in_page.md",
      "guides/learning/telemetry.md"
    ]
  end

  defp groups_for_extras do
    [
      Introduction: ~r{guides/(overview|introduction/.+)\.md},
      Learning: ~r{guides/learning/.+}
    ]
  end

  defp groups_for_modules do
    [
      Providers: [
        ~r/^Amur\.Providers(\.|$)/
      ],
      Core: [
        Amur,
        Amur.Router,
        Amur.Controller,
        Amur.Page
      ],
      Extending: [
        Amur.Provider,
        Amur.Callback,
        Amur.User
      ],
      Telemetry: [
        Amur.Telemetry.Events
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp aliases do
    [
      {:"test.coverage", ["test --cover"]},
      ci: [
        "test",
        "credo --strict",
        "format --check-formatted",
        "deps.audit",
        "dialyzer",
        "sobelow"
      ]
    ]
  end

  defp deps do
    [
      {:assent, "~> 0.3"},
      {:plug, ">= 0.0.0"},
      {:telemetry, "~> 1.4"},
      {:igniter, "~> 0.8.4", optional: true},

      # Test & Dev
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:mix_audit, "~> 2.1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.15.0", only: [:dev, :test], runtime: false}
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
