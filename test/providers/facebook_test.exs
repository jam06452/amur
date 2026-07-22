defmodule Amur.Providers.FacebookTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Facebook

  test "strategy/0 returns the expected strategy module" do
    assert Facebook.strategy() == Assent.Strategy.Facebook
  end

  test "base_config/0 includes email scope" do
    assert Keyword.get(Facebook.base_config(), :authorization_params) == [scope: "email"]
  end

  test "normalize_user/1 returns normalized map" do
    user = %{
      "sub" => "123",
      "email" => "foo@example.com",
      "name" => "Foo",
      "picture" => "http://a"
    }

    normalized = Facebook.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo"
    assert normalized.avatar == "http://a"
  end
end
