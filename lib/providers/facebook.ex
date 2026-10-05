defmodule Amur.Providers.Facebook do
  @moduledoc """
  Facebook OAuth provider for Amur.

  Wraps `Assent.Strategy.Facebook` and talks to the Graph API at
  `https://graph.facebook.com/v4.0`, fetching the user from `/me`.

  ## Configuration

  Sends the client secret in the request body
  (`auth_method: :client_secret_post`).

  Default scope: `email`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, `name` to `:name`, and `picture`
  to `:avatar`.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Facebook

  @impl true
  def base_config do
    [
      base_url: "https://graph.facebook.com/v4.0",
      authorize_url: "https://www.facebook.com/v4.0/dialog/oauth",
      token_url: "/oauth/access_token",
      user_url: "/me",
      authorization_params: [scope: "email"],
      auth_method: :client_secret_post
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
