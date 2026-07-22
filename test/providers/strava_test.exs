defmodule Amur.Providers.StravaTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Strava

  test "strategy/0 returns the expected strategy module" do
    assert Strava.strategy() == Assent.Strategy.Strava
  end

  test "base_config/0 includes read_all,profile:read_all scope" do
    assert Keyword.get(Strava.base_config(), :authorization_params) == [
             scope: "read_all,profile:read_all"
           ]
  end

  test "normalize_user/1 uses preferred_username when present" do
    user = %{
      "sub" => "456",
      "preferred_username" => "john_doe",
      "given_name" => "John",
      "family_name" => "Doe",
      "picture" => "http://b"
    }

    normalized = Strava.normalize_user(user)

    assert normalized.uid == "456"
    assert normalized.name == "john_doe"
    assert normalized.avatar == "http://b"
  end

  test "normalize_user/1 falls back to given_name and family_name" do
    user = %{
      "sub" => "789",
      "given_name" => "Jane",
      "family_name" => "Smith",
      "picture" => "http://c"
    }

    normalized = Strava.normalize_user(user)

    assert normalized.uid == "789"
    assert normalized.name == "Jane Smith"
    assert normalized.avatar == "http://c"
  end

  test "normalize_user/1 does not include email key" do
    user = %{
      "sub" => "101",
      "preferred_username" => "foo",
      "picture" => "http://d"
    }

    normalized = Strava.normalize_user(user)

    assert normalized.uid == "101"
    assert normalized.name == "foo"
    assert normalized.avatar == "http://d"
    refute Map.has_key?(normalized, :email)
  end
end
