defmodule Amur.Providers.Linkedin do
  @moduledoc """
  LinkedIn OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Linkedin

  def base_config do
    [
      base_url: "https://www.linkedin.com/oauth",
      authorization_params: [scope: "profile email"],
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
