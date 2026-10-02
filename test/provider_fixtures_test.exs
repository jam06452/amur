defmodule Amur.ProviderFixtures do
  @provider_names [
    :apple,
    :auth0,
    :azure_ad,
    :basecamp,
    :bitbucket,
    :digital_ocean,
    :discord,
    :facebook,
    :github,
    :gitlab,
    :google,
    :instagram,
    :line,
    :linkedin,
    :slack,
    :spotify,
    :strava,
    :stripe,
    :telegram,
    :twitch,
    :twitter,
    :vk,
    :zitadel
  ]

  def provider_names, do: @provider_names ++ [:hackclub]

  def user(:hackclub) do
    %{
      "identity" => %{
        "id" => "fixture-id",
        "primary_email" => "fixture@example.com",
        "first_name" => "Fixture",
        "last_name" => "User",
        "slack_id" => "U123"
      }
    }
  end

  def user(_provider) do
    %{
      "sub" => "fixture-id",
      "id" => "fixture-id",
      "email" => "fixture@example.com",
      "name" => "Fixture User",
      "given_name" => "Fixture",
      "family_name" => "User",
      "preferred_username" => "fixture-user",
      "picture" => "https://example.com/fixture.png"
    }
  end
end

defmodule Amur.ProviderFixturesTest do
  use ExUnit.Case, async: true

  @providers %{
    apple: Amur.Providers.Apple,
    auth0: Amur.Providers.Auth0,
    azure_ad: Amur.Providers.AzureAD,
    basecamp: Amur.Providers.Basecamp,
    bitbucket: Amur.Providers.Bitbucket,
    digital_ocean: Amur.Providers.DigitalOcean,
    discord: Amur.Providers.Discord,
    facebook: Amur.Providers.Facebook,
    github: Amur.Providers.GitHub,
    gitlab: Amur.Providers.Gitlab,
    google: Amur.Providers.Google,
    hackclub: Amur.Providers.HackClub,
    instagram: Amur.Providers.Instagram,
    line: Amur.Providers.LINE,
    linkedin: Amur.Providers.Linkedin,
    slack: Amur.Providers.Slack,
    spotify: Amur.Providers.Spotify,
    strava: Amur.Providers.Strava,
    stripe: Amur.Providers.Stripe,
    telegram: Amur.Providers.Telegram,
    twitch: Amur.Providers.Twitch,
    twitter: Amur.Providers.Twitter,
    vk: Amur.Providers.VK,
    zitadel: Amur.Providers.Zitadel
  }

  for provider <- Amur.ProviderFixtures.provider_names() do
    test "#{provider} fixture normalizes through its provider module" do
      module = Map.fetch!(@providers, unquote(provider))
      normalized = module.normalize_user(Amur.ProviderFixtures.user(unquote(provider)))

      assert is_map(normalized)
      assert normalized.uid == "fixture-id"
    end
  end
end
