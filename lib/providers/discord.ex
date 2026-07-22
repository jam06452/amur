defmodule Amur.Providers.Discord do
  @moduledoc """
  Discord OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Discord

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

  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["preferred_username"],
      avatar: user["picture"]
    }
  end
end
