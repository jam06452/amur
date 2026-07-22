defmodule Amur.Providers.Apple do
  @moduledoc """
  Apple Sign In OAuth provider for Amur.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Apple

  def base_config do
    [
      base_url: "https://appleid.apple.com",
      authorization_params: [scope: "email", response_mode: "form_post"],
      client_authentication_method: "client_secret_post"
    ]
  end

  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: "#{user["given_name"]} #{user["family_name"]}",
      avatar: nil
    }
  end
end
