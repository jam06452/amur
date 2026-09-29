defmodule Amur.Providers.Reddit do
  @moduledoc """
  Reddit OAuth provider for Amur.

  Tokens are requested with `duration: "permanent"` so that a refresh
  token is issued alongside the one hour access token.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.OAuth2

  @impl true
  def base_config do
    [
      base_url: "https://www.reddit.com/api/v1",
      authorize_url: "/authorize",
      token_url: "/access_token",
      user_url: "https://oauth.reddit.com/api/v1/me",
      auth_method: :client_secret_basic,
      authorization_params: [scope: "identity", duration: "permanent"]
    ]
  end

  @impl true
  def normalize_user(user) do
    %{
      uid: uid(user["id"]),
      name: user["name"],
      avatar: user["icon_img"]
    }
  end

  # The account endpoint may return the id with or without the "t2_" thing
  # prefix depending on the API version.
  defp uid("t2_" <> id), do: id
  defp uid(id), do: id
end
