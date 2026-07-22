defmodule Amur.Providers.Strava do
  @moduledoc """
  Strava OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Strava

  def base_config do
    [
      base_url: "https://www.strava.com/api/v3",
      authorize_url: "https://www.strava.com/oauth/authorize",
      token_url: "/oauth/token",
      user_url: "/athlete",
      authorization_params: [scope: "read_all,profile:read_all"],
      auth_method: :client_secret_post
    ]
  end

  def normalize_user(user) do
    %{
      uid: user["sub"],
      name: user["preferred_username"] || "#{user["given_name"]} #{user["family_name"]}",
      avatar: user["picture"]
    }
  end
end
