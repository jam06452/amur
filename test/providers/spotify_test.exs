defmodule Amur.Providers.SpotifyTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Spotify

  test "strategy/0 returns the expected strategy module" do
    assert Spotify.strategy() == Assent.Strategy.Spotify
  end

  test "base_config/0 includes user-read-email scope" do
    assert Keyword.get(Spotify.base_config(), :authorization_params) == [scope: "user-read-email"]
  end

  test "normalize_user/1 returns normalized map with name" do
    user = %{
      "sub" => "456",
      "email" => "bar@example.com",
      "name" => "Bar",
      "preferred_username" => "bar",
      "picture" => "http://b"
    }

    normalized = Spotify.normalize_user(user)

    assert normalized.uid == "456"
    assert normalized.email == "bar@example.com"
    assert normalized.name == "Bar"
    assert normalized.avatar == "http://b"
  end

  test "normalize_user/1 falls back to preferred_username when name is absent" do
    user = %{
      "sub" => "789",
      "email" => "baz@example.com",
      "preferred_username" => "baz",
      "picture" => "http://c"
    }

    normalized = Spotify.normalize_user(user)

    assert normalized.uid == "789"
    assert normalized.email == "baz@example.com"
    assert normalized.name == "baz"
    assert normalized.avatar == "http://c"
  end
end
