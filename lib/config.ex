defmodule Amur.Config do
  @moduledoc false

  # Resolves provider names into the modules and configuration used by Amur.
  #
  # Provider configuration is read from the `:amur` application environment:
  #
  #   * `:providers` maps provider names to credential keyword lists or custom
  #     provider modules.
  #   * `:base_url` supplies the base used to build a provider's callback URI.
  #
  # Built-in provider modules are registered in `@built_ins`. Custom modules
  # take precedence when the same provider name is configured explicitly. The
  # returned configuration combines the provider's defaults with application
  # credentials and includes the strategy and redirect URI required by
  # `Amur.Controller`.

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

  # Returns the atoms of all built-in providers, sorted alphabetically.
  def built_in_providers do
    @built_ins
    |> Map.keys()
    |> Enum.sort()
  end

  # Returns the provider names configured for the application, in the order
  # they were declared. Only names that resolve to a usable provider are
  # returned, so the sign-in page never links to a provider that would fail.
  def configured_providers do
    :amur
    |> Application.get_env(:providers, [])
    |> Keyword.keys()
    |> Enum.filter(&match?({:ok, _}, resolve(&1)))
  end

  # Reports whether a provider name is configured and maps to a usable module,
  # without building its configuration.
  #
  # `resolve/1` calls `module.base_config/0`, which is provider code and may be
  # expensive or raise. This predicate answers the same question as `resolve/1`
  # for a *configured* name - is there a module to dispatch to - using only the
  # shape of the configured value, so it is safe to call before a span opens to
  # label telemetry. A provider whose `base_config/0` raises is still resolvable:
  # the name is valid and the failure belongs to the provider, not the lookup.
  #
  # `nil` is an atom but not a module, so it is excluded explicitly: a
  # `providers: [foo: nil]` entry would otherwise be reported as resolvable while
  # `resolve/1` raises on `nil.base_config/0`.
  #
  # Public only because `Amur.Controller` calls it; not part of the documented
  # API (the module is `@moduledoc false`).
  def resolvable?(provider) when is_atom(provider) and not is_nil(provider) do
    case Keyword.fetch(Application.get_env(:amur, :providers, []), provider) do
      {:ok, module} when is_atom(module) and not is_nil(module) -> true
      {:ok, _credentials} -> Map.has_key?(@built_ins, provider)
      :error -> false
    end
  end

  def resolvable?(_provider), do: false

  # Resolves a provider name supplied by a router or application.
  #
  # Binary names are converted only to existing atoms, preventing arbitrary
  # request parameters from growing the VM atom table. Atom names are resolved
  # against configured custom modules and built-in providers. Unknown names
  # return `{:error, :unknown_provider}`.
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

  # A malformed request parameter (for example `?provider[]=x`, which Plug parses
  # as a list) is not a provider name, so it fails cleanly rather than raising a
  # `FunctionClauseError` from the guards above.
  def resolve(_provider), do: {:error, :unknown_provider}

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
