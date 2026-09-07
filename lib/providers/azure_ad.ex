defmodule Amur.Providers.AzureAD do
  @moduledoc """
  Azure AD OAuth provider for Amur.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.AzureAD

  @impl true
  def base_config do
    [
      authorization_params: [scope: "email profile", response_mode: "form_post"],
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
