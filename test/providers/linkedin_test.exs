defmodule Amur.Providers.LinkedinTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Linkedin

  test "strategy/0 returns the expected strategy module" do
    assert Linkedin.strategy() == Assent.Strategy.Linkedin
  end

  test "base_config/0 includes profile email scope" do
    assert Keyword.get(Linkedin.base_config(), :authorization_params) == [scope: "profile email"]
  end

  test "normalize_user/1 returns normalized map" do
    user = %{
      "sub" => "123",
      "email" => "foo@example.com",
      "name" => "Foo",
      "picture" => "http://a"
    }

    normalized = Linkedin.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo"
    assert normalized.avatar == "http://a"
  end
end
