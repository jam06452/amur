defmodule Amur.Providers.Facebook do
  @moduledoc """
  Facebook OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Facebook

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

  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["name"],
      avatar: user["picture"]
    }
  end
end
