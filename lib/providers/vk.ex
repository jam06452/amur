defmodule Amur.Providers.VK do
  @moduledoc """
  VK OAuth provider for Amur.
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
