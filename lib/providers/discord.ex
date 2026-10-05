defmodule Amur.Providers.Discord do
  @moduledoc """
  Discord OAuth provider for Amur.

  Wraps `Assent.Strategy.Discord` and talks to `https://discordapp.com/api`,
  fetching the current user from `/users/@me`.

  ## Configuration

  Sends the client secret in the request body
  (`auth_method: :client_secret_post`).

  Default scope: `identify email`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, `preferred_username` to `:name`,
  and `picture` to `:avatar`.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Discord

  @impl true
  def base_config do
    [
      base_url: "https://discordapp.com/api",
      authorize_url: "/oauth2/authorize",
      token_url: "/oauth2/token",
      user_url: "/users/@me",
      authorization_params: [scope: "identify email"],
      auth_method: :client_secret_post
    ]
  end

  @impl true
  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["preferred_username"],
      avatar: user["picture"]
    }
  end
end
