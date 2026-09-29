defmodule Amur.Providers.Authentik do
  @moduledoc """
  Authentik OpenID Connect provider for Amur.

  Set `base_url` to your application's provider path, e.g.
  `https://authentik.example.com/application/o/my-app`, configured through
  `AUTHENTIK_BASE_URL` in `config/runtime.exs`. Discovery uses this application
  path even when Authentik is configured with a global issuer. ID tokens are
  validated against the issuer advertised in the discovery document.

  Configure an RS256 signing key and include the desired profile claims in ID
  tokens; user normalization reads ID-token claims rather than userinfo.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.OIDC

  @impl true
  def base_config do
    [
      openid_configuration_uri: "/.well-known/openid-configuration/",
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
