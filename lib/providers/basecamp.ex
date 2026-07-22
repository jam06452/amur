defmodule Amur.Providers.Basecamp do
  @moduledoc """
  Basecamp OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Basecamp

  def base_config do
    [
      base_url: "https://launchpad.37signals.com",
      authorize_url: "/authorization/new",
      token_url: "/authorization/token",
      user_url: "/authorization.json",
      authorization_params: [type: "web_server"],
      auth_method: :client_secret_post
    ]
  end

  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["name"]
    }
  end
end
