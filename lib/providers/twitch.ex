defmodule Amur.Providers.Twitch do
  @moduledoc """
  Twitch OAuth provider for Amur.

  Wraps `Assent.Strategy.Twitch` and talks to `https://id.twitch.tv/oauth2`.

  ## Configuration

  Requests the `user:read:email` scope and asks Twitch to include the `email`,
  `email_verified`, `picture`, and `preferred_username` claims in the ID token
  via the `claims` authorization parameter.

  Sends the client secret in the request body
  (`client_authentication_method: "client_secret_post"`).

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, and `picture` to `:avatar`. For
  `:name` it prefers `preferred_username`, falling back to `name`.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Twitch

  @impl true
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

  @impl true
  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["preferred_username"] || user["name"],
      avatar: user["picture"]
    }
  end
end
