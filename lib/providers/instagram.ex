defmodule Amur.Providers.Instagram do
  @moduledoc """
  Instagram OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Instagram

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

  def normalize_user(user) do
    %{
      uid: user["sub"],
      name: user["preferred_username"] || user["name"]
    }
  end
end
