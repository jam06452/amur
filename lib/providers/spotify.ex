defmodule Amur.Providers.Spotify do
  @moduledoc """
  Spotify OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Spotify

  def base_config do
    [
      base_url: "https://api.spotify.com/v1",
      authorize_url: "https://accounts.spotify.com/authorize",
      token_url: "https://accounts.spotify.com/api/token",
      user_url: "/me",
      authorization_params: [scope: "user-read-email"],
      auth_method: :client_secret_post
    ]
  end

  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["name"] || user["preferred_username"],
      avatar: user["picture"]
    }
  end
end
