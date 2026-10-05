defmodule Amur.Providers.Gitlab do
  @moduledoc """
  GitLab OAuth provider for Amur.

  Wraps `Assent.Strategy.Gitlab` and defaults to `https://gitlab.com`. For a
  self-hosted instance, override `:base_url` in your provider config.

  ## Configuration

  Sends the client secret in the request body
  (`client_authentication_method: "client_secret_post"`).

  Default scope: `email profile`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, `name` to `:name`, and `picture`
  to `:avatar`.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Gitlab

  @impl true
  def base_config do
    [
      base_url: "https://gitlab.com",
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
