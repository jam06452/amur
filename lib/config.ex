defmodule Amur.Config do
  @moduledoc """
  Configuration resolver for OAuth providers.
  """

  @built_ins %{
    github: Amur.Providers.GitHub,
    google: Amur.Providers.Google,
    hackclub: Amur.Providers.HackClub
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

    {scopes, credentials} = Keyword.pop(credentials, :scopes)

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
