defmodule Amur.Providers.AzureAD do
  @moduledoc """
  Azure AD (Microsoft Entra ID) OAuth provider for Amur.

  Wraps `Assent.Strategy.AzureAD`.

  ## Configuration

  Uses `response_mode: "form_post"`, so the callback arrives as a `POST` body
  rather than query parameters. Amur's router handles this transparently
  because `Amur.Controller.callback/2` receives the merged params.

  Sends the client secret in the request body
  (`client_authentication_method: "client_secret_post"`).

  Default scope: `email profile`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, `name` to `:name`, and `picture`
  to `:avatar`.
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
