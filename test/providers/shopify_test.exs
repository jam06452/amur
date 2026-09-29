defmodule Amur.Providers.ShopifyTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Shopify

  test "strategy/0 returns the expected strategy module" do
    assert Shopify.strategy() == Assent.Strategy.OAuth2
  end

  test "base_config/0 uses the shop OAuth endpoints" do
    config = Shopify.base_config()

    assert Keyword.get(config, :authorize_url) == "/admin/oauth/authorize"
    assert Keyword.get(config, :token_url) == "/admin/oauth/access_token"
    assert config |> Keyword.get(:user_url) |> String.starts_with?("/admin/api/")
    assert Keyword.get(config, :auth_method) == :client_secret_post
  end

  test "base_config/0 includes a default access scope" do
    assert Shopify.base_config() |> Keyword.get(:authorization_params) ==
             [scope: "read_products"]
  end

  test "normalize_user/1 normalizes the shop as the user" do
    user = %{
      "shop" => %{
        "id" => 548_380_009,
        "name" => "John Smith Test Store",
        "email" => "j.smith@example.com",
        "domain" => "shop.example.com"
      }
    }

    normalized = Shopify.normalize_user(user)

    assert normalized.uid == "548380009"
    assert normalized.name == "John Smith Test Store"
    assert normalized.email == "j.smith@example.com"
    assert normalized.domain == "shop.example.com"
  end

  test "normalize_user/1 handles a missing shop object" do
    normalized = Shopify.normalize_user(%{})

    assert normalized.uid == nil
    assert normalized.name == nil
    assert normalized.email == nil
    assert normalized.domain == nil
  end
end
