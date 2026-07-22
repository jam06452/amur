defmodule Amur.Providers.Bitbucket do
  @moduledoc """
  Bitbucket OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Bitbucket

  def base_config do
    [
      base_url: "https://api.bitbucket.org/2.0",
      authorize_url: "https://bitbucket.org/site/oauth2/authorize",
      token_url: "https://bitbucket.org/site/oauth2/access_token",
      user_url: "/user",
      authorization_params: [scope: "account email"],
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
