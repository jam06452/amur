defmodule Amur.Providers.Shopify do
  @moduledoc """
  Shopify OAuth provider for Amur.

  Set `base_url` to your shop's domain, e.g.
  `https://your-store.myshopify.com`. The shop is normalized as the user,
  since Shopify's authorization grants access to a store rather than to a
  staff member.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.OAuth2

  @impl true
  def base_config do
    [
      authorize_url: "/admin/oauth/authorize",
      token_url: "/admin/oauth/access_token",
      user_url: "/admin/api/2026-07/shop.json",
      auth_method: :client_secret_post,
      authorization_params: [scope: "read_products"]
    ]
  end

  @impl true
  def normalize_user(user) do
    shop = user["shop"] || %{}

    %{
      uid: shop["id"] && to_string(shop["id"]),
      name: shop["name"],
      email: shop["email"],
      domain: shop["domain"]
    }
  end
end
