defmodule Amur.Providers.StripeTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Stripe

  test "strategy/0 returns the expected strategy module" do
    assert Stripe.strategy() == Assent.Strategy.Stripe
  end

  test "base_config/0 includes base_url and auth_method" do
    config = Stripe.base_config()

    assert Keyword.get(config, :base_url) == "https://api.stripe.com/"
    assert Keyword.get(config, :auth_method) == :client_secret_post
  end

  test "normalize_user/1 returns normalized map with only uid and email" do
    user = %{
      "sub" => "acct_123",
      "email" => "merchant@example.com",
      "name" => "Merchant",
      "preferred_username" => "merchant",
      "picture" => "http://example.com/avatar.png"
    }

    normalized = Stripe.normalize_user(user)

    assert normalized.uid == "acct_123"
    assert normalized.email == "merchant@example.com"
    refute Map.has_key?(normalized, :name)
    refute Map.has_key?(normalized, :avatar)
  end
end
