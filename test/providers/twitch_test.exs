defmodule Amur.Providers.TwitchTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Twitch

  test "strategy/0 returns the expected strategy module" do
    assert Twitch.strategy() == Assent.Strategy.Twitch
  end

  test "base_config/0 includes user:read:email scope and claims" do
    expected_auth_params = [
      scope: "user:read:email",
      claims:
        "{\"id_token\":{\"email\":null,\"email_verified\":null,\"picture\":null,\"preferred_username\":null}}"
    ]

    assert Keyword.get(Twitch.base_config(), :authorization_params) == expected_auth_params
  end

  test "normalize_user/1 returns normalized map with preferred_username name" do
    user = %{
      "sub" => "123",
      "email" => "foo@example.com",
      "preferred_username" => "foo"
    }

    normalized = Twitch.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "foo"
    assert normalized.avatar == nil
  end
end
