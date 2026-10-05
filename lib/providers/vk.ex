defmodule Amur.Providers.VK do
  @moduledoc """
  VK OAuth provider for Amur.

  Wraps `Assent.Strategy.VK`. Authorization goes to
  `https://oauth.vk.com/*`, while the user is fetched from the API method
  `https://api.vk.com/method/users.get`.

  ## Configuration

  Sends the client secret in the request body
  (`auth_method: :client_secret_post`).

  Default scope: `email`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, and `picture` to `:avatar`. The
  name is built by joining `given_name` and `family_name` with a space.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.VK

  @impl true
  def base_config do
    [
      base_url: "https://api.vk.com",
      authorize_url: "https://oauth.vk.com/authorize",
      token_url: "https://oauth.vk.com/access_token",
      user_url: "/method/users.get",
      authorization_params: [scope: "email"],
      auth_method: :client_secret_post
    ]
  end

  @impl true
  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: "#{user["given_name"]} #{user["family_name"]}",
      avatar: user["picture"]
    }
  end
end
