defmodule Amur.Providers.Google do
  @moduledoc """
  Google OAuth provider for Amur.

  Wraps `Assent.Strategy.Google` (OpenID Connect).

  ## Configuration

  Default scope: `email profile`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, `name` to `:name`, and `picture`
  to `:avatar`.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Google

  @impl true
  def base_config do
    [authorization_params: [scope: "email profile"]]
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
