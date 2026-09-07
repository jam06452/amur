defmodule Amur.Providers.Linkedin do
  @moduledoc """
  LinkedIn OAuth provider for Amur.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Linkedin

  @impl true
  def base_config do
    [
      base_url: "https://www.linkedin.com/oauth",
      authorization_params: [scope: "profile email"],
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
