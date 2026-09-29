defmodule Amur.Providers.RedditTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Reddit

  test "strategy/0 returns the expected strategy module" do
    assert Reddit.strategy() == Assent.Strategy.OAuth2
  end

  test "base_config/0 uses the api/v1 endpoints and basic auth" do
    config = Reddit.base_config()

    assert Keyword.get(config, :base_url) == "https://www.reddit.com/api/v1"
    assert Keyword.get(config, :authorize_url) == "/authorize"
    assert Keyword.get(config, :token_url) == "/access_token"
    assert Keyword.get(config, :user_url) == "https://oauth.reddit.com/api/v1/me"
    assert Keyword.get(config, :auth_method) == :client_secret_basic
  end

  test "base_config/0 requests the identity scope with a permanent duration" do
    assert Reddit.base_config() |> Keyword.get(:authorization_params) ==
             [scope: "identity", duration: "permanent"]
  end

  test "normalize_user/1 returns normalized map" do
    user = %{"id" => "t2_abc123", "name" => "foo", "icon_img" => "http://a"}

    normalized = Reddit.normalize_user(user)

    assert normalized.uid == "abc123"
    assert normalized.name == "foo"
    assert normalized.avatar == "http://a"
  end

  test "normalize_user/1 keeps a bare account id intact" do
    normalized = Reddit.normalize_user(%{"id" => "abc123", "name" => "foo"})

    assert normalized.uid == "abc123"
  end
end
