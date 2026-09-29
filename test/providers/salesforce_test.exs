defmodule Amur.Providers.SalesforceTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Salesforce

  test "strategy/0 returns the expected strategy module" do
    assert Salesforce.strategy() == Assent.Strategy.OAuth2
  end

  test "base_config/0 uses the production oauth2 endpoints" do
    config = Salesforce.base_config()

    assert Keyword.get(config, :base_url) == "https://login.salesforce.com"
    assert Keyword.get(config, :authorize_url) == "/services/oauth2/authorize"
    assert Keyword.get(config, :token_url) == "/services/oauth2/token"
    assert Keyword.get(config, :user_url) == "/services/oauth2/userinfo"
    assert Keyword.get(config, :auth_method) == :client_secret_basic
  end

  test "base_config/0 includes openid email profile scope" do
    assert Salesforce.base_config() |> Keyword.get(:authorization_params) ==
             [scope: "openid email profile"]
  end

  test "normalize_user/1 returns normalized map" do
    user = %{
      "sub" => "005123",
      "email" => "foo@example.com",
      "name" => "Foo Bar",
      "picture" => "http://a"
    }

    normalized = Salesforce.normalize_user(user)

    assert normalized.uid == "005123"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo Bar"
    assert normalized.avatar == "http://a"
  end
end
