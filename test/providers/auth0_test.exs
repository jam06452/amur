defmodule Amur.Providers.Auth0Test do
  use ExUnit.Case, async: true

  alias Amur.Providers.Auth0

  test "strategy/0 returns the expected strategy module" do
    assert Auth0.strategy() == Assent.Strategy.Auth0
  end

  test "base_config/0 includes email profile scope" do
    assert Keyword.get(Auth0.base_config(), :authorization_params) == [scope: "email profile"]
  end

  test "normalize_user/1 returns normalized map with string uid" do
    user = %{
      "sub" => "123",
      "email" => "foo@example.com",
      "name" => "Foo",
      "picture" => "http://a"
    }

    normalized = Auth0.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo"
    assert normalized.avatar == "http://a"
  end
end
