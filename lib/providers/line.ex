defmodule Amur.Providers.LINE do
  @moduledoc """
  LINE OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.LINE

  def base_config do
    [
      base_url: "https://access.line.me",
      authorization_params: [scope: "email profile", response_type: "code"],
      id_token_signed_response_alg: "HS256"
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
