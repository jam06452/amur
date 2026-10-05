defmodule Amur.Providers.Stripe do
  @moduledoc """
  Stripe OAuth provider for Amur.

  Wraps `Assent.Strategy.Stripe` (Stripe Connect). Authorization and token
  requests go to `https://connect.stripe.com/oauth/*`, while the account is
  fetched from `https://api.stripe.com/v1/account`.

  ## Configuration

  Sends the client secret in the request body
  (`auth_method: :client_secret_post`).

  Sets no default scope; Stripe relies on its own defaults.

  ## Normalized user

  Maps `sub` to `:uid` and `email` to `:email`. Stripe returns no name or
  avatar, so those keys are omitted.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Stripe

  @impl true
  def base_config do
    [
      base_url: "https://api.stripe.com/",
      authorize_url: "https://connect.stripe.com/oauth/authorize",
      token_url: "https://connect.stripe.com/oauth/token",
      user_url: "/v1/account",
      auth_method: :client_secret_post
    ]
  end

  @impl true
  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"]
    }
  end
end
