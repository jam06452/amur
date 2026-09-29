defmodule Amur.Providers.KeycloakTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Keycloak

  test "strategy/0 returns the expected strategy module" do
    assert Keycloak.strategy() == Assent.Strategy.OIDC
  end

  test "base_config/0 leaves endpoints to OIDC discovery" do
    config = Keycloak.base_config()

    refute Keyword.has_key?(config, :base_url)
    refute Keyword.has_key?(config, :authorize_url)
    refute Keyword.has_key?(config, :token_url)
    refute Keyword.has_key?(config, :user_url)
    assert config[:client_authentication_method] == "client_secret_basic"
  end

  test "base_config/0 includes email profile scope (OIDC adds openid)" do
    assert Keycloak.base_config() |> Keyword.get(:authorization_params) ==
             [scope: "email profile"]
  end

  defmodule DiscoveryAdapter do
    @behaviour Assent.HTTPAdapter

    @impl true
    def request(:get, url, _body, _headers, _opts) do
      send(self(), {:discovery_url, url})

      {:ok,
       %Assent.HTTPAdapter.HTTPResponse{
         status: 200,
         body: %{
           "authorization_endpoint" =>
             "https://keycloak.example.com/realms/myrealm/protocol/openid-connect/auth"
         }
       }}
    end
  end

  test "authorization discovers endpoints from the configured realm" do
    config =
      Keyword.merge(Keycloak.base_config(),
        base_url: "https://keycloak.example.com/realms/myrealm",
        client_id: "client-id",
        redirect_uri: "https://app.example.com/auth/keycloak/callback",
        http_adapter: DiscoveryAdapter
      )

    assert {:ok, %{url: url, session_params: session_params}} =
             Keycloak.strategy().authorize_url(config)

    assert_received {:discovery_url,
                     "https://keycloak.example.com/realms/myrealm/.well-known/openid-configuration"}

    uri = URI.parse(url)
    assert uri.scheme == "https"
    assert uri.host == "keycloak.example.com"
    assert uri.path == "/realms/myrealm/protocol/openid-connect/auth"
    params = URI.decode_query(uri.query)
    assert params["scope"] == "openid email profile"
    assert Enum.count(String.split(params["scope"]), &(&1 == "openid")) == 1
    assert params["client_id"] == "client-id"
    assert params["redirect_uri"] == "https://app.example.com/auth/keycloak/callback"
    assert is_binary(session_params.state)
    assert params["state"] == session_params.state
  end

  test "normalize_user/1 returns normalized map" do
    user = %{
      "sub" => "123",
      "email" => "foo@example.com",
      "name" => "Foo Bar",
      "preferred_username" => "foo",
      "picture" => "http://a"
    }

    normalized = Keycloak.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo Bar"
    assert normalized.avatar == "http://a"
  end

  test "normalize_user/1 falls back to preferred_username when name is missing" do
    normalized = Keycloak.normalize_user(%{"sub" => "123", "preferred_username" => "foo"})

    assert normalized.name == "foo"
  end
end
