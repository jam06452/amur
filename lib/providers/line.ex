defmodule Amur.Providers.LINE do
  @moduledoc """
  LINE OAuth provider for Amur.

  Wraps `Assent.Strategy.LINE` and talks to `https://access.line.me`.

  ## Configuration

  Uses `response_type: "code"` and signs the ID token with `HS256`
  (`id_token_signed_response_alg: "HS256"`).

  Default scope: `email profile`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, `name` to `:name`, and `picture`
  to `:avatar`.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.LINE

  @impl true
  def base_config do
    [
      base_url: "https://access.line.me",
      authorization_params: [scope: "email profile", response_type: "code"],
      id_token_signed_response_alg: "HS256"
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
