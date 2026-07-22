defmodule Amur.Providers.GitlabTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Gitlab

  test "strategy/0 returns the expected strategy module" do
    assert Gitlab.strategy() == Assent.Strategy.Gitlab
  end

  test "base_config/0 includes email profile scope" do
    assert Keyword.get(Gitlab.base_config(), :authorization_params) == [scope: "email profile"]
  end

  test "normalize_user/1 returns normalized map with string uid" do
    user = %{
      "sub" => "123",
      "email" => "foo@example.com",
      "name" => "Foo",
      "picture" => "http://a"
    }

    normalized = Gitlab.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo"
    assert normalized.avatar == "http://a"
  end
end
