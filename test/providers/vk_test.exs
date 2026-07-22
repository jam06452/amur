defmodule Amur.Providers.VKTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.VK

  test "strategy/0 returns the expected strategy module" do
    assert VK.strategy() == Assent.Strategy.VK
  end

  test "base_config/0 includes email scope" do
    assert Keyword.get(VK.base_config(), :authorization_params) == [scope: "email"]
  end

  test "normalize_user/1 returns normalized map with string uid" do
    user = %{
      "sub" => "123",
      "email" => "foo@example.com",
      "given_name" => "Foo",
      "family_name" => "Bar",
      "picture" => "http://a"
    }

    normalized = VK.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo Bar"
    assert normalized.avatar == "http://a"
  end
end
