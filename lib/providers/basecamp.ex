defmodule Amur.Providers.Basecamp do
  @moduledoc """
  Basecamp OAuth provider for Amur.

  Wraps `Assent.Strategy.Basecamp` and talks to the 37signals Launchpad at
  `https://launchpad.37signals.com`.

  ## Configuration

  Uses the `web_server` authorization type and sends the client secret in the
  request body (`auth_method: :client_secret_post`).

  Sets no default scope; Basecamp relies on its own defaults.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, and `name` to `:name`. No avatar
  is returned.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Basecamp

  @impl true
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

  @impl true
  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["name"]
    }
  end
end
