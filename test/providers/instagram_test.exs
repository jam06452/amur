defmodule Amur.Providers.InstagramTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Instagram

  test "strategy/0 returns the expected strategy module" do
    assert Instagram.strategy() == Assent.Strategy.Instagram
  end

  test "base_config/0 includes user_profile scope" do
    assert Keyword.get(Instagram.base_config(), :authorization_params) == [scope: "user_profile"]
  end

  test "normalize_user/1 returns normalized map with only uid and name, no email or avatar" do
    user = %{
      "sub" => "123",
      "name" => "Foo",
      "preferred_username" => "bar"
    }

    normalized = Instagram.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.name == "bar"
    refute Map.has_key?(normalized, :email)
    refute Map.has_key?(normalized, :avatar)
  end
end
