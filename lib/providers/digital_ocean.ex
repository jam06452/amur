defmodule Amur.Providers.DigitalOcean do
  @moduledoc """
  DigitalOcean OAuth provider for Amur.

  Wraps `Assent.Strategy.DigitalOcean`. Authorization and token requests go to
  `https://cloud.digitalocean.com/v1/oauth/*`, while the account is fetched
  from the `https://api.digitalocean.com` API.

  ## Configuration

  Sends the client secret in the request body
  (`auth_method: :client_secret_post`).

  Default scope: `read write`.

  ## Normalized user

  Maps `sub` to `:uid` and `email` to `:email`. DigitalOcean returns no name or
  avatar, so those keys are omitted.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.DigitalOcean

  @impl true
  def base_config do
    [
      base_url: "https://api.digitalocean.com",
      authorize_url: "https://cloud.digitalocean.com/v1/oauth/authorize",
      token_url: "https://cloud.digitalocean.com/v1/oauth/token",
      user_url: "/v2/account",
      authorization_params: [scope: "read write", response_type: "code"],
      auth_method: :client_secret_post
    ]
  end

  @impl true
  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"]
    }
  end
end
