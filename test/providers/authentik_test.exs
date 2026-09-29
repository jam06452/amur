defmodule Amur.Providers.AuthentikTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Authentik

  test "strategy/0 returns the expected strategy module" do
    assert Authentik.strategy() == Assent.Strategy.OIDC
  end

  test "base_config/0 leaves endpoints to OIDC discovery" do
    config = Authentik.base_config()

    refute Keyword.has_key?(config, :base_url)
    refute Keyword.has_key?(config, :authorize_url)
    refute Keyword.has_key?(config, :token_url)
    refute Keyword.has_key?(config, :user_url)
    assert config[:client_authentication_method] == "client_secret_basic"
    assert config[:openid_configuration_uri] == "/.well-known/openid-configuration/"
  end

  test "base_config/0 includes email profile scope (OIDC adds openid)" do
    assert Authentik.base_config() |> Keyword.get(:authorization_params) ==
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
           "authorization_endpoint" => "https://authentik.example.com/application/o/authorize/"
         }
       }}
    end
  end

  test "authorization discovers endpoints from the configured application path" do
    config =
      Keyword.merge(Authentik.base_config(),
        base_url: "https://authentik.example.com/application/o/my-app",
        client_id: "client-id",
        redirect_uri: "https://app.example.com/auth/authentik/callback",
        http_adapter: DiscoveryAdapter
      )

    assert {:ok, %{url: url, session_params: session_params}} =
             Authentik.strategy().authorize_url(config)

    assert_received {:discovery_url,
                     "https://authentik.example.com/application/o/my-app/.well-known/openid-configuration/"}

    uri = URI.parse(url)
    assert uri.scheme == "https"
    assert uri.host == "authentik.example.com"
    assert uri.path == "/application/o/authorize/"
    params = URI.decode_query(uri.query)
    assert params["scope"] == "openid email profile"
    assert Enum.count(String.split(params["scope"]), &(&1 == "openid")) == 1
    assert params["client_id"] == "client-id"
    assert params["redirect_uri"] == "https://app.example.com/auth/authentik/callback"
    assert is_binary(session_params.state)
    assert params["state"] == session_params.state
  end

  test "normalize_user/1 returns normalized map" do
    user = %{
      "sub" => "a90f5b2e-1234",
      "email" => "foo@example.com",
      "name" => "Foo Bar",
      "preferred_username" => "foo",
      "picture" => "http://a"
    }

    normalized = Authentik.normalize_user(user)

    assert normalized.uid == "a90f5b2e-1234"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo Bar"
    assert normalized.avatar == "http://a"
  end

  test "normalize_user/1 falls back to preferred_username when name is missing" do
    normalized = Authentik.normalize_user(%{"sub" => "1", "preferred_username" => "foo"})

    assert normalized.name == "foo"
  end
end
