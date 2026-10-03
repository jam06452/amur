defmodule Amur.ConfigTest do
  use ExUnit.Case, async: false

  defmodule CustomProvider do
    use Amur.Provider

    @impl true
    def strategy, do: Assent.Strategy.OAuth2

    @impl true
    def base_config do
      [base_url: "https://custom.example.com", authorization_params: [scope: "email"]]
    end

    @impl true
    def normalize_user(user), do: %{uid: user["id"]}
  end

  setup do
    previous =
      for key <- [:providers, :base_url],
          into: %{},
          do: {key, Application.get_env(:amur, key)}

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:amur, key),
          else: Application.put_env(:amur, key, value)
      end
    end)

    :ok
  end

  test "resolve/1 returns unknown for invalid string" do
    assert {:error, :unknown_provider} = Amur.Config.resolve("nope")
  end

  test "built_in_providers/0 returns all built-in provider atoms sorted" do
    providers = Amur.Config.built_in_providers()

    assert :apple in providers
    assert :github in providers
    assert :zitadel in providers
    assert providers == Enum.sort(providers)
    assert length(providers) == 24
  end

  test "resolve/1 returns unknown for unconfigured atom" do
    Application.put_env(:amur, :providers, [])
    assert {:error, :unknown_provider} = Amur.Config.resolve(:github)
  end

  test "resolve/1 builds config when provider configured with credentials" do
    Application.put_env(:amur, :providers, github: [client_id: "id", client_secret: "sec"])

    assert {:ok, {module, config}} = Amur.Config.resolve(:github)
    assert module == Amur.Providers.GitHub
    assert config[:client_id] == "id"
    assert config[:client_secret] == "sec"
    assert config[:strategy] == module.strategy()
  end

  test "resolve/1 builds config when provider configured as a custom module" do
    Application.put_env(:amur, :providers, custom: Amur.ConfigTest.CustomProvider)

    assert {:ok, {module, config}} = Amur.Config.resolve(:custom)
    assert module == Amur.ConfigTest.CustomProvider
    assert config[:strategy] == module.strategy()
    assert config[:base_url] == "https://custom.example.com"
    assert config[:authorization_params] == [scope: "email"]
    assert config[:redirect_uri] == "/auth/custom/callback"
  end

  test "resolve/1 returns unknown for custom provider not in config" do
    Application.put_env(:amur, :providers, [])
    assert {:error, :unknown_provider} = Amur.Config.resolve(:custom)
  end

  test "resolve/1 rejects credentials for an unknown configured provider" do
    Application.put_env(:amur, :providers, unknown: [client_id: "id"])

    assert {:error, :unknown_provider} = Amur.Config.resolve(:unknown)
  end

  test "resolve/1 overrides an existing authorization scope" do
    Application.put_env(:amur, :providers, github: [scopes: "repo"])

    assert {:ok, {_module, config}} = Amur.Config.resolve(:github)
    assert config[:authorization_params] == [scope: "repo"]
  end

  test "resolve/1 adds authorization scope when provider has no defaults" do
    Application.put_env(:amur, :providers, telegram: [scopes: "openid", client_id: "id"])

    assert {:ok, {_module, config}} = Amur.Config.resolve(:telegram)
    assert config[:authorization_params] == [scope: "openid"]
  end

  test "configured_providers/0 returns configured provider names in order" do
    Application.put_env(:amur, :providers, github: [], google: [], discord: [])

    assert Amur.Config.configured_providers() == [:github, :google, :discord]
  end

  test "configured_providers/0 omits providers that do not resolve" do
    Application.put_env(:amur, :providers, github: [], nope: [])

    assert Amur.Config.configured_providers() == [:github]
  end

  test "configured_providers/0 includes custom provider modules" do
    Application.put_env(:amur, :providers, custom: Amur.ConfigTest.CustomProvider)

    assert Amur.Config.configured_providers() == [:custom]
  end

  test "configured_providers/0 returns an empty list when nothing is configured" do
    Application.put_env(:amur, :providers, [])

    assert Amur.Config.configured_providers() == []
  end
end
