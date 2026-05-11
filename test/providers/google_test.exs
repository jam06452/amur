defmodule Amur.Providers.GoogleTest do
  use ExUnit.Case, async: true

  test "strategy/0 returns the expected strategy module" do
    assert Amur.Providers.Google.strategy() == Assent.Strategy.Google
  end

  test "base_config/0 includes email profile scope" do
    assert Keyword.get(Amur.Providers.Google.base_config(), :authorization_params) == [
             scope: "email profile"
           ]
  end

  test "normalize_user/1 returns normalized map" do
    user = %{
      "sub" => "abc123",
      "email" => "g@example.com",
      "name" => "G",
      "picture" => "http://p"
    }

    normalized = Amur.Providers.Google.normalize_user(user)

    assert normalized.uid == "abc123"
    assert normalized.email == "g@example.com"
    assert normalized.name == "G"
    assert normalized.avatar == "http://p"
  end
end
