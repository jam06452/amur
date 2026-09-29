defmodule Amur.ConfigTest do
  use ExUnit.Case, async: false

  defmodule CustomProvider do
    use Amur.Provider

    @impl true
    def strategy, do: Assent.Strategy.OAuth2

    @impl true
    def base_config do
      [base_url: "custom.example.com", authorization_params: [scope: "email"]]
    end

    @impl true
    def normalize_user(user), do: %{uid: user["id"]}
  end

  defmodule DiscoveryAdapter do
    @behaviour Assent.HTTPAdapter

    @impl true
    def request(:get, url, _body, _headers, _opts) do
      send(self(), {:discovery_url, url})

      {:ok,
       %Assent.HTTPAdapter.HTTPResponse{
         status: 200,
         body: %{"authorization_endpoint" => "https://tenant.auth0.com/authorize"}
       }}
    end
  end

  setup do
    for key <- [:providers, :base_url] do
      original = Application.fetch_env(:amur, key)
      Application.delete_env(:amur, key)

      on_exit(fn ->
        case original do
          {:ok, value} -> Application.put_env(:amur, key, value)
          :error -> Application.delete_env(:amur, key)
        end
      end)
    end

    :ok
  end

  test "resolve/1 returns unknown for invalid string" do
    assert {:error, :unknown_provider} = Amur.Config.resolve("nope")
  end

  test "built_in_providers/0 returns all built-in provider atoms sorted" do
    providers = Amur.Config.built_in_providers()

    assert :apple in providers
    assert :github in providers
    assert :keycloak in providers
    assert :zitadel in providers
    assert providers == Enum.sort(providers)
    assert length(providers) == 32
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

  test "resolve/1 prepends HTTPS to scheme-less provider base URLs" do
    for provider <- Amur.Config.built_in_providers(),
        url <- ["tenant.auth0.com", "identity.example.com:8443/realms/app"] do
      Application.put_env(:amur, :providers, [{provider, [base_url: url]}])

      assert {:ok, {_module, config}} = Amur.Config.resolve(provider)
      assert config[:base_url] == "https://" <> url
    end
  end

  test "Auth0 authorization fetches discovery over HTTPS for a bare domain" do
    Application.put_env(:amur, :base_url, "app.example.com")

    Application.put_env(:amur, :providers,
      auth0: [
        base_url: "tenant.auth0.com",
        client_id: "client-id",
        http_adapter: DiscoveryAdapter
      ]
    )

    assert {:ok, {module, config}} = Amur.Config.resolve(:auth0)
    assert {:ok, %{url: url}} = module.strategy().authorize_url(config)
    assert_received {:discovery_url, "https://tenant.auth0.com/.well-known/openid-configuration"}

    uri = URI.parse(url)
    assert uri.scheme == "https"
    assert uri.host == "tenant.auth0.com"
    assert uri.path == "/authorize"

    assert URI.decode_query(uri.query)["redirect_uri"] ==
             "https://app.example.com/auth/auth0/callback"
  end

  test "resolve/1 preserves explicit HTTP and HTTPS provider URLs" do
    for url <- ["https://tenant.auth0.com", "http://localhost:8080/realms/app"] do
      Application.put_env(:amur, :providers, auth0: [base_url: url])

      assert {:ok, {_module, config}} = Amur.Config.resolve(:auth0)
      assert config[:base_url] == url
    end
  end

  test "resolve/1 normalizes the application base URL used for callbacks" do
    Application.put_env(:amur, :providers, auth0: [])

    for {url, expected} <- [
          {"app.example.com", "https://app.example.com"},
          {"localhost:4000", "https://localhost:4000"},
          {"https://app.example.com", "https://app.example.com"},
          {"http://localhost:4000", "http://localhost:4000"},
          {"", ""}
        ] do
      Application.put_env(:amur, :base_url, url)

      assert {:ok, {_module, config}} = Amur.Config.resolve(:auth0)
      assert config[:redirect_uri] == expected <> "/auth/auth0/callback"
      refute Keyword.has_key?(config, :base_url)
    end
  end

  test "resolve/1 preserves an explicit redirect URI" do
    Application.put_env(:amur, :base_url, "app.example.com")

    Application.put_env(:amur, :providers,
      auth0: [redirect_uri: "http://localhost:4000/callback"]
    )

    assert {:ok, {_module, config}} = Amur.Config.resolve(:auth0)
    assert config[:redirect_uri] == "http://localhost:4000/callback"
  end

  test "resolve/1 returns unknown for custom provider not in config" do
    Application.put_env(:amur, :providers, [])
    assert {:error, :unknown_provider} = Amur.Config.resolve(:custom)
  end
end
