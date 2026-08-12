defmodule Amur.ConfigTest do
  use ExUnit.Case, async: true

  defmodule CustomProvider do
    use Amur.Provider

    def strategy, do: Assent.Strategy.OAuth2

    def base_config do
      [base_url: "https://custom.example.com", authorization_params: [scope: "email"]]
    end

    def normalize_user(user), do: %{uid: user["id"]}
  end

  setup do
    # Ensure clean env between tests
    on_exit(fn -> Application.delete_env(:amur, :providers) end)
    :ok
  end

  test "resolve/1 returns unknown for invalid string" do
    assert {:error, :unknown_provider} = Amur.Config.resolve("nope")
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
end
