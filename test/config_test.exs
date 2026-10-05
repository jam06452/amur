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

  test "resolve/1 returns unknown for a string that is not an existing atom" do
    # Guards the atom-table safety: a request parameter must not be able to
    # grow the VM atom table, so an unknown binary resolves to an error rather
    # than being converted with `String.to_atom/1`.
    assert {:error, :unknown_provider} =
             Amur.Config.resolve("amur_definitely_not_an_existing_atom")
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

  test "resolve/1 and resolvable?/1 agree for a nil module value" do
    # `nil` is an atom but not a module. `resolve/1` must not call
    # `nil.base_config/0`, and `resolvable?/1` must not claim the name is usable:
    # the two share `provider_module/1` so they cannot disagree.
    Application.put_env(:amur, :providers, foo: nil)

    assert Amur.Config.resolvable?(:foo) == false
    assert {:error, :unknown_provider} = Amur.Config.resolve(:foo)
    assert {:error, :unknown_provider} = Amur.Config.resolve("foo")
  end

  test "configured_providers/0 does not crash on a nil module value" do
    # A `providers: [github: nil]` entry is treated like `github: []`: the name
    # falls back to the built-in, so it resolves and is listed. A non-built-in
    # name with a nil value resolves to nothing and is omitted.
    Application.put_env(:amur, :providers, github: nil, foo: nil)

    assert Amur.Config.configured_providers() == [:github]
  end

  test "resolvable?/1 agrees with resolve/1 for every configured shape" do
    Application.put_env(:amur, :providers,
      github: [client_id: "id"],
      custom: Amur.ConfigTest.CustomProvider,
      weird: "not-a-module",
      foo: nil
    )

    for name <- [:github, :custom, :weird, :foo, :nope] do
      resolvable? = Amur.Config.resolvable?(name)
      resolves? = match?({:ok, _}, Amur.Config.resolve(name))

      assert resolvable? == resolves?,
             "resolvable?(#{inspect(name)}) = #{resolvable?} but resolve/1 resolved? = #{resolves?}"
    end
  end
end
