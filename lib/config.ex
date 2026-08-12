defmodule Amur.Config do
  @moduledoc """
  Configuration resolver for OAuth providers.
  """

  @built_ins %{
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

  def resolve(provider) when is_binary(provider) do
    provider
    |> String.to_existing_atom()
    |> resolve()
  rescue
    ArgumentError -> {:error, :unknown_provider}
  end

  def resolve(provider) when is_atom(provider) do
    configured_providers = Application.get_env(:amur, :providers, [])

    case Keyword.fetch(configured_providers, provider) do
      {:ok, module} when is_atom(module) ->
        build_config(module, provider)

      {:ok, _credentials} ->
        case Map.fetch(@built_ins, provider) do
          {:ok, module} -> build_config(module, provider)
          :error -> {:error, :unknown_provider}
        end

      :error ->
        {:error, :unknown_provider}
    end
  end

  defp build_config(module, provider) do
    configured_providers = Application.get_env(:amur, :providers, [])
    base_url = Application.get_env(:amur, :base_url, "")
    credentials = Keyword.get(configured_providers, provider, [])

    {scopes, credentials} =
      if is_list(credentials),
        do: Keyword.pop(credentials, :scopes),
        else: {nil, []}

    config =
      module.base_config()
      |> Keyword.merge(credentials)
      |> Keyword.put(:strategy, module.strategy())
      |> Keyword.put_new(:redirect_uri, "#{base_url}/auth/#{provider}/callback")
      |> merge_scopes(scopes)

    {:ok, {module, config}}
  end

  defp merge_scopes(config, nil), do: config

  defp merge_scopes(config, scopes) do
    Keyword.update(config, :authorization_params, [scope: scopes], fn params ->
      Keyword.put(params, :scope, scopes)
    end)
  end
end
