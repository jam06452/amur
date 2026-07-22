defmodule Amur.Providers.BasecampTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Basecamp

  test "strategy/0 returns the expected strategy module" do
    assert Basecamp.strategy() == Assent.Strategy.Basecamp
  end

  test "base_config/0 includes type: \"web_server\" authorization_params" do
    assert Keyword.get(Basecamp.base_config(), :authorization_params) == [type: "web_server"]
  end

  test "normalize_user/1 returns normalized map with uid, email, name (no avatar)" do
    user = %{
      "sub" => "123",
      "email" => "foo@example.com",
      "name" => "Foo"
    }

    normalized = Basecamp.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo"
    refute Map.has_key?(normalized, :avatar)
  end
end
