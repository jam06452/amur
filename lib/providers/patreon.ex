defmodule Amur.Providers.Patreon do
  @moduledoc """
  Patreon OAuth provider for Amur.

  The `identity[email]` scope is required for the user's email to be
  included in the identity endpoint response.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.OAuth2

  @impl true
  def base_config do
    [
      base_url: "https://www.patreon.com",
      authorize_url: "/oauth2/authorize",
      token_url: "/api/oauth2/token",
      user_url: "/api/oauth2/v2/identity?fields%5Buser%5D=email,full_name,thumb_url",
      auth_method: :client_secret_post,
      authorization_params: [scope: "identity identity[email]"]
    ]
  end

  @impl true
  def normalize_user(user) do
    data = user["data"] || %{}
    attributes = Map.get(data, "attributes", %{})

    %{
      uid: data["id"],
      email: attributes["email"],
      name: attributes["full_name"],
      avatar: attributes["thumb_url"]
    }
  end
end
