defmodule Amur.Providers.Twitch do
  @moduledoc """
  Twitch OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Twitch

  def base_config do
    [
      base_url: "https://id.twitch.tv/oauth2",
      authorization_params: [
        scope: "user:read:email",
        claims:
          "{\"id_token\":{\"email\":null,\"email_verified\":null,\"picture\":null,\"preferred_username\":null}}"
      ],
      client_authentication_method: "client_secret_post"
    ]
  end

  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["preferred_username"] || user["name"],
      avatar: user["picture"]
    }
  end
end
