defmodule Amur.Providers.AppleTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Apple

  test "strategy/0 returns the expected strategy module" do
    assert Apple.strategy() == Assent.Strategy.Apple
  end

  test "base_config/0 includes the expected authorization_params" do
    assert Keyword.get(Apple.base_config(), :authorization_params) == [
             scope: "email",
             response_mode: "form_post"
           ]
  end

  test "normalize_user/1 returns normalized map with nil avatar" do
    user = %{
      "sub" => "001234.abcdef",
      "email" => "apple@example.com",
      "given_name" => "John",
      "family_name" => "Appleseed"
    }

    normalized = Apple.normalize_user(user)

    assert normalized.uid == "001234.abcdef"
    assert normalized.email == "apple@example.com"
    assert normalized.name == "John Appleseed"
    assert normalized.avatar == nil
  end
end
