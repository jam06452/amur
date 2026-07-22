defmodule Amur.Providers.Twitter do
  @moduledoc """
  Twitter OAuth 1.0 provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Twitter

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

  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["name"],
      avatar: user["picture"]
    }
  end
end
