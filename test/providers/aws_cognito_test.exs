defmodule Amur.Providers.AWSCognitoTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.AWSCognito

  test "strategy/0 returns the expected strategy module" do
    assert AWSCognito.strategy() == Assent.Strategy.OIDC
  end

  test "base_config/0 leaves endpoints to OIDC discovery" do
    config = AWSCognito.base_config()

    refute Keyword.has_key?(config, :base_url)
    refute Keyword.has_key?(config, :authorize_url)
    refute Keyword.has_key?(config, :token_url)
    refute Keyword.has_key?(config, :user_url)
    assert config[:client_authentication_method] == "client_secret_basic"
  end

  test "base_config/0 includes email profile scope (OIDC adds openid)" do
    assert AWSCognito.base_config() |> Keyword.get(:authorization_params) ==
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
             "https://example.auth.us-east-1.amazoncognito.com/oauth2/authorize"
         }
       }}
    end
  end

  test "authorization discovers hosted UI endpoints from the configured issuer" do
    config =
      Keyword.merge(AWSCognito.base_config(),
        base_url: "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_Example",
        client_id: "client-id",
        redirect_uri: "https://app.example.com/auth/aws_cognito/callback",
        http_adapter: DiscoveryAdapter
      )

    assert {:ok, %{url: url, session_params: session_params}} =
             AWSCognito.strategy().authorize_url(config)

    assert_received {:discovery_url,
                     "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_Example/.well-known/openid-configuration"}

    uri = URI.parse(url)
    assert uri.host == "example.auth.us-east-1.amazoncognito.com"
    assert uri.path == "/oauth2/authorize"
    params = URI.decode_query(uri.query)
    assert params["scope"] == "openid email profile"
    assert params["client_id"] == "client-id"
    assert params["redirect_uri"] == "https://app.example.com/auth/aws_cognito/callback"
    assert params["state"] == session_params.state
  end

  test "normalize_user/1 returns normalized map" do
    user = %{
      "sub" => "a1b2c3d4-5678",
      "email" => "foo@example.com",
      "name" => "Foo Bar",
      "username" => "foo",
      "picture" => "http://a"
    }

    normalized = AWSCognito.normalize_user(user)

    assert normalized.uid == "a1b2c3d4-5678"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo Bar"
    assert normalized.avatar == "http://a"
  end

  test "normalize_user/1 falls back to username when name is missing" do
    normalized = AWSCognito.normalize_user(%{"sub" => "1", "username" => "foo"})

    assert normalized.name == "foo"
  end
end
