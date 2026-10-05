defmodule Amur.Providers.Slack do
  @moduledoc """
  Slack OAuth provider for Amur.

  Wraps `Assent.Strategy.Slack` using Slack's OpenID Connect flow.

  ## Configuration

  Sends the client secret in the request body
  (`client_authentication_method: "client_secret_post"`).

  Default scope: `openid email profile`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, `name` to `:name`, and `picture`
  to `:avatar`.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Slack

  @impl true
  def base_config do
    [
      base_url: "https://slack.com",
      authorization_params: [scope: "openid email profile"],
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
