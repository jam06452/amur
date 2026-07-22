defmodule Amur.Providers.Gitlab do
  @moduledoc """
  GitLab OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Gitlab

  def base_config do
    [
      base_url: "https://gitlab.com",
      authorization_params: [scope: "email profile"],
      client_authentication_method: "client_secret_post"
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
