defmodule Amur.Providers.GitHubTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.GitHub

  test "strategy/0 returns the expected strategy module" do
    assert GitHub.strategy() == Assent.Strategy.Github
  end

  test "base_config/0 includes user:email scope" do
    assert Keyword.get(GitHub.base_config(), :authorization_params) == [scope: "user:email"]
  end

  test "normalize_user/1 returns normalized map with string uid" do
    user = %{
      "sub" => "123",
      "email" => "foo@example.com",
      "name" => "Foo",
      "preferred_username" => "foo",
      "picture" => "http://a"
    }

    normalized = GitHub.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "foo"
    assert normalized.avatar == "http://a"
  end
end
