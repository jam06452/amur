defmodule Amur.Providers.SlackTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Slack

  test "strategy/0 returns the expected strategy module" do
    assert Slack.strategy() == Assent.Strategy.Slack
  end

  test "base_config/0 includes openid email profile scope" do
    assert Keyword.get(Slack.base_config(), :authorization_params) == [
             scope: "openid email profile"
           ]
  end

  test "normalize_user/1 returns normalized map with string uid" do
    user = %{
      "sub" => "123",
      "email" => "foo@example.com",
      "name" => "Foo",
      "picture" => "http://a"
    }

    normalized = Slack.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo"
    assert normalized.avatar == "http://a"
  end
end
