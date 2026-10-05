defmodule Amur.Providers.Linkedin do
  @moduledoc """
  LinkedIn OAuth provider for Amur.

  Wraps `Assent.Strategy.Linkedin` (Sign In with LinkedIn v2).

  ## Configuration

  Sends the client secret in the request body
  (`client_authentication_method: "client_secret_post"`).

  Default scope: `profile email`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, `name` to `:name`, and `picture`
  to `:avatar`.
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
