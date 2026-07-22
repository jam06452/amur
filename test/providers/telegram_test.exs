defmodule Amur.Providers.TelegramTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Telegram

  test "strategy/0 returns the expected strategy module" do
    assert Telegram.strategy() == Assent.Strategy.Telegram
  end

  test "base_config/0 returns an empty list" do
    assert Telegram.base_config() == []
  end

  test "normalize_user/1 with given_name and family_name builds name correctly" do
    user = %{
      "sub" => "123",
      "given_name" => "John",
      "family_name" => "Doe",
      "preferred_username" => "johndoe",
      "picture" => "http://a"
    }

    normalized = Telegram.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.name == "John Doe"
    assert normalized.avatar == "http://a"
    refute Map.has_key?(normalized, :email)
  end

  test "normalize_user/1 falls back to preferred_username when given_name and family_name are absent" do
    user = %{
      "sub" => "456",
      "preferred_username" => "telegramuser",
      "picture" => "http://b"
    }

    normalized = Telegram.normalize_user(user)

    assert normalized.uid == "456"
    assert normalized.name == "telegramuser"
    assert normalized.avatar == "http://b"
    refute Map.has_key?(normalized, :email)
  end

  test "normalize_user/1 does not include email in the normalized map" do
    user = %{
      "sub" => "789",
      "given_name" => "Alice",
      "preferred_username" => "alice",
      "picture" => "http://c"
    }

    normalized = Telegram.normalize_user(user)

    refute Map.has_key?(normalized, :email)
  end
end
