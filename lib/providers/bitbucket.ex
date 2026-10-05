defmodule Amur.Providers.Bitbucket do
  @moduledoc """
  Bitbucket OAuth provider for Amur.

  Wraps `Assent.Strategy.Bitbucket`. Authorization and token requests go to
  `https://bitbucket.org/site/oauth2/*`, while the user is fetched from the
  `https://api.bitbucket.org/2.0` API.

  ## Configuration

  Sends the client secret in the request body
  (`auth_method: :client_secret_post`).

  Default scope: `account email`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, `name` to `:name`, and `picture`
  to `:avatar`.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Bitbucket

  @impl true
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
