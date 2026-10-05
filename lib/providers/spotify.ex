defmodule Amur.Providers.Spotify do
  @moduledoc """
  Spotify OAuth provider for Amur.

  Wraps `Assent.Strategy.Spotify`. Authorization goes to
  `https://accounts.spotify.com/*`, while the profile is fetched from the Web
  API at `https://api.spotify.com/v1/me`.

  ## Configuration

  Sends the client secret in the request body
  (`auth_method: :client_secret_post`).

  Default scope: `user-read-email`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, and `picture` to `:avatar`. For
  `:name` it prefers `name`, falling back to `preferred_username`.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Spotify

  @impl true
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
