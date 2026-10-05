defmodule Amur.Providers.Twitter do
  @moduledoc """
  Twitter (X) OAuth 1.0 provider for Amur.

  Wraps `Assent.Strategy.Twitter` and talks to `https://api.twitter.com`.

  This is the only built-in provider that uses **OAuth 1.0** rather than
  OAuth 2.0. As a result there is no scope parameter, and the token returned to
  your `:on_success` callback carries `oauth_token` and `oauth_token_secret`
  instead of `access_token`.

  ## Configuration

  Uses the 1.1 `account/verify_credentials` endpoint, requesting the user's
  email (`include_email=true`).

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, `name` to `:name`, and `picture`
  to `:avatar`.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Twitter

  @impl true
  def base_config do
    [
      base_url: "https://api.twitter.com",
      request_token_url: "/oauth/request_token",
      authorize_url: "/oauth/authenticate",
      access_token_url: "/oauth/access_token",
      user_url:
        "/1.1/account/verify_credentials.json?include_entities=false&skip_status=true&include_email=true"
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
