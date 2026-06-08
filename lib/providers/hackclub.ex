defmodule Amur.Providers.HackClub do
  @moduledoc """
  Hack Club OAuth provider for Amur.
  """
  use Amur.Provider

  def strategy, do: Assent.Strategy.OAuth2

  def base_config do
    [
      base_url: "https://auth.hackclub.com",
      authorize_url: "/oauth/authorize",
      token_url: "/oauth/token",
      user_url: "/api/v1/me",
      auth_method: :client_secret_post,
      authorization_params: [scope: "email slack_id"]
    ]
  end

  def normalize_user(user) do
    identity = user["identity"]

    %{
      uid: identity["id"],
      email: identity["primary_email"],
      name: "#{identity["first_name"]} #{identity["last_name"]}"
    }
  end
end
