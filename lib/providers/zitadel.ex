defmodule Amur.Providers.Zitadel do
  @moduledoc """
  Zitadel OAuth provider for Amur.

  Wraps `Assent.Strategy.Zitadel`. Zitadel is a self-hostable identity
  platform, so the endpoints come from your instance and are supplied through
  your config.

  ## Configuration

  Zitadel is treated as a public client: no client secret is sent
  (`client_authentication_method: "none"`) and PKCE is enabled
  (`code_verifier: true`).

  Default scope: `email profile`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, `name` to `:name`, and `picture`
  to `:avatar`.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Zitadel

  @impl true
  def base_config do
    [
      authorization_params: [scope: "email profile"],
      client_authentication_method: "none",
      code_verifier: true
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
