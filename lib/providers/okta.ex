defmodule Amur.Providers.Okta do
  @moduledoc """
  Okta OpenID Connect provider for Amur.

  Set `base_url` to your authorization server's issuer URL, e.g.
  `https://your-org.okta.com/oauth2/default` (or the path of a custom
  authorization server such as `/oauth2/ausxxxxxxxxxxxxxxx`).
  Configure this through `OKTA_BASE_URL` in `config/runtime.exs`.
  Endpoints are discovered from the authorization server's OpenID configuration.

  User normalization reads validated ID-token claims. Configure the authorization
  server to include the desired profile claims in ID tokens.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.OIDC

  @impl true
  def base_config do
    [
      client_authentication_method: "client_secret_basic",
      authorization_params: [scope: "profile email"]
    ]
  end

  @impl true
  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["name"] || user["preferred_username"],
      avatar: user["picture"]
    }
  end
end
