defmodule Amur.Providers.Auth0 do
  @moduledoc """
  Auth0 OAuth provider for Amur.

  Wraps `Assent.Strategy.Auth0`. Auth0 is a multi-tenant identity platform, so
  the endpoints are derived from your tenant domain and supplied through your
  config rather than hard-coded here.

  ## Configuration

  Sends the client secret in the request body
  (`client_authentication_method: "client_secret_post"`).

  Default scope: `email profile`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, `name` to `:name`, and `picture`
  to `:avatar`.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Auth0

  @impl true
  def base_config do
    [
      authorization_params: [scope: "email profile"],
      client_authentication_method: "client_secret_post"
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
