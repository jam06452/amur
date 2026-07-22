defmodule Amur.Providers.Stripe do
  @moduledoc """
  Stripe OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Stripe

  def base_config do
    [
      base_url: "https://api.stripe.com/",
      authorize_url: "https://connect.stripe.com/oauth/authorize",
      token_url: "https://connect.stripe.com/oauth/token",
      user_url: "/v1/account",
      auth_method: :client_secret_post
    ]
  end

  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"]
    }
  end
end
