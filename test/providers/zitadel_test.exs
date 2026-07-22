defmodule Amur.Providers.ZitadelTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Zitadel

  test "strategy/0 returns the expected strategy module" do
    assert Zitadel.strategy() == Assent.Strategy.Zitadel
  end

  test "base_config/0 includes email profile scope, none auth method, and code_verifier: true" do
    config = Zitadel.base_config()

    assert Keyword.get(config, :authorization_params) == [scope: "email profile"]
    assert Keyword.get(config, :client_authentication_method) == "none"
    assert Keyword.get(config, :code_verifier) == true
  end

  test "normalize_user/1 returns normalized map with string uid" do
    user = %{
      "sub" => "456",
      "email" => "bar@example.com",
      "name" => "Bar",
      "picture" => "https://a"
    }

    normalized = Zitadel.normalize_user(user)

    assert normalized.uid == "456"
    assert normalized.email == "bar@example.com"
    assert normalized.name == "Bar"
    assert normalized.avatar == "https://a"
  end
end
