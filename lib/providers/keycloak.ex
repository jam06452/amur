defmodule Amur.Providers.Keycloak do
  @moduledoc """
  Keycloak OpenID Connect provider for Amur.

  Set `base_url` to your realm's issuer URL, e.g.
  `https://keycloak.example.com/realms/myrealm` (or
  `https://keycloak.example.com/auth/realms/myrealm` for Keycloak < 17).
  Configure this through `KEYCLOAK_BASE_URL` in `config/runtime.exs`.
  Endpoints are discovered from the realm's OpenID configuration.

  User normalization reads validated ID-token claims. Ensure the client's
  protocol mappers include the desired profile claims in ID tokens.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.OIDC

  @impl true
  def base_config do
    [
      client_authentication_method: "client_secret_basic",
      authorization_params: [scope: "email profile"]
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
