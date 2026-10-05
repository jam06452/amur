defmodule Amur.Providers.Instagram do
  @moduledoc """
  Instagram OAuth provider for Amur.

  Wraps `Assent.Strategy.Instagram`. Authorization goes to
  `https://api.instagram.com/oauth/*`, while the profile is fetched from the
  Instagram Graph API at `https://graph.instagram.com`.

  ## Configuration

  Sends the client secret in the request body
  (`auth_method: :client_secret_post`).

  Default scope: `user_profile`.

  ## Normalized user

  Maps `sub` to `:uid` and falls back from `preferred_username` to `name` for
  `:name`. Instagram returns no email or avatar, so those keys are omitted.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Instagram

  @impl true
  def base_config do
    [
      base_url: "https://graph.instagram.com",
      authorize_url: "https://api.instagram.com/oauth/authorize",
      token_url: "https://api.instagram.com/oauth/access_token",
      user_url: "/me",
      authorization_params: [scope: "user_profile"],
      auth_method: :client_secret_post
    ]
  end

  @impl true
  def normalize_user(user) do
    %{
      uid: user["sub"],
      name: user["preferred_username"] || user["name"]
    }
  end
end
