defmodule Amur.Providers.DigitalOceanTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.DigitalOcean

  test "strategy/0 returns the expected strategy module" do
    assert DigitalOcean.strategy() == Assent.Strategy.DigitalOcean
  end

  test "base_config/0 includes read write scope" do
    assert Keyword.get(DigitalOcean.base_config(), :authorization_params) == [
             scope: "read write",
             response_type: "code"
           ]
  end

  test "normalize_user/1 returns normalized map with only uid and email" do
    user = %{
      "sub" => "123",
      "email" => "foo@example.com"
    }

    normalized = DigitalOcean.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.email == "foo@example.com"
    refute Map.has_key?(normalized, :name)
    refute Map.has_key?(normalized, :avatar)
  end
end
