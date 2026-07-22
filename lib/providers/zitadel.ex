defmodule Amur.Providers.Zitadel do
  @moduledoc """
  Zitadel OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Zitadel

  def base_config do
    [
      authorization_params: [scope: "email profile"],
      client_authentication_method: "none",
      code_verifier: true
    ]
  end

  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["name"],
      avatar: user["picture"]
    }
  end
end
