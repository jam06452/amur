defmodule Amur.Providers.TwitterTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Twitter

  test "strategy/0 returns the expected strategy module" do
    assert Twitter.strategy() == Assent.Strategy.Twitter
  end

  test "base_config/0 includes the correct base_url" do
    assert Keyword.get(Twitter.base_config(), :base_url) == "https://api.twitter.com"
  end

  test "normalize_user/1 returns normalized map" do
    user = %{
      "sub" => "123",
      "email" => "foo@example.com",
      "name" => "Foo",
      "picture" => "http://a"
    }

    normalized = Twitter.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo"
    assert normalized.avatar == "http://a"
  end
end
