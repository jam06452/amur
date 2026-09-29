defmodule Amur.Providers.AWSCognito do
  @moduledoc """
  AWS Cognito OpenID Connect provider for Amur.

  In `config/runtime.exs`, set `base_url: System.fetch_env!("AWS_COGNITO_BASE_URL")`
  in the `aws_cognito` provider configuration. Use your user pool's issuer URL,
  e.g. `https://cognito-idp.us-east-1.amazonaws.com/us-east-1_Example`, not the
  hosted UI domain. Authorization, token, and userinfo endpoints are discovered
  from the issuer's OpenID configuration.
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
      name: user["name"] || user["username"],
      avatar: user["picture"]
    }
  end
end
