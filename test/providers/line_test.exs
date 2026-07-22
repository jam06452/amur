defmodule Amur.Providers.LINETest do
  use ExUnit.Case, async: true

  alias Amur.Providers.LINE

  test "strategy/0 returns the expected strategy module" do
    assert LINE.strategy() == Assent.Strategy.LINE
  end

  test "base_config/0 includes email profile scope and HS256 alg" do
    config = LINE.base_config()

    assert Keyword.get(config, :authorization_params) == [
             scope: "email profile",
             response_type: "code"
           ]

    assert Keyword.get(config, :id_token_signed_response_alg) == "HS256"
  end

  test "normalize_user/1 returns normalized map" do
    user = %{
      "sub" => "12345",
      "email" => "user@example.com",
      "name" => "Jane Doe",
      "picture" => "https://example.com/avatar.png"
    }

    normalized = LINE.normalize_user(user)

    assert normalized.uid == "12345"
    assert normalized.email == "user@example.com"
    assert normalized.name == "Jane Doe"
    assert normalized.avatar == "https://example.com/avatar.png"
  end
end
