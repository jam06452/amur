defmodule Amur.Providers.Salesforce do
  @moduledoc """
  Salesforce OAuth provider for Amur.

  Defaults to the production login endpoint; set `base_url` to
  `https://test.salesforce.com` for sandboxes. Add the `refresh_token`
  scope to the provider config if your app needs refresh tokens.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.OAuth2

  @impl true
  def base_config do
    [
      base_url: "https://login.salesforce.com",
      authorize_url: "/services/oauth2/authorize",
      token_url: "/services/oauth2/token",
      user_url: "/services/oauth2/userinfo",
      auth_method: :client_secret_basic,
      authorization_params: [scope: "openid email profile"]
    ]
  end

  @impl true
  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["name"],
      avatar: user["picture"]
    }
  end
end
