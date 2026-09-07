defmodule Amur.Providers.Auth0 do
  @moduledoc """
  Auth0 OAuth provider for Amur.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Auth0

  @impl true
  def base_config do
    [
      authorization_params: [scope: "email profile"],
      client_authentication_method: "client_secret_post"
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
