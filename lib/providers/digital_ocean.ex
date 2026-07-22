defmodule Amur.Providers.DigitalOcean do
  @moduledoc """
  DigitalOcean OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.DigitalOcean

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

  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"]
    }
  end
end
