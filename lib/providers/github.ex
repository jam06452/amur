defmodule Amur.Providers.GitHub do
  @moduledoc """
  GitHub OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Github

  def base_config do
    [authorization_params: [scope: "user:email"]]
  end

  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["preferred_username"],
      avatar: user["picture"]
    }
  end
end
