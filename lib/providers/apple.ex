defmodule Amur.Providers.Apple do
  @moduledoc """
  Apple Sign In OAuth provider for Amur.

  Wraps `Assent.Strategy.Apple` and talks to `https://appleid.apple.com`.

  ## Configuration

  Uses `response_mode: "form_post"`, so Apple delivers the callback as a `POST`
  body rather than query parameters. Amur's router handles this transparently
  because `Amur.Controller.callback/2` receives the merged params.

  The client secret is sent in the request body
  (`client_authentication_method: "client_secret_post"`).

  Default scope: `email`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, and joins `given_name` and
  `family_name` into `:name`. Apple never returns an avatar, so `:avatar` is
  always `nil`.

  > #### Name on first sign-in {: .info}
  >
  > Apple only includes `given_name`/`family_name` on the very first
  > authorization for a given app. On subsequent sign-ins `:name` will be
  > `" "` (an empty join), so persist the name from the first callback.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Apple

  @impl true
  def base_config do
    [
      base_url: "https://appleid.apple.com",
      authorization_params: [scope: "email", response_mode: "form_post"],
      client_authentication_method: "client_secret_post"
    ]
  end

  @impl true
  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: "#{user["given_name"]} #{user["family_name"]}",
      avatar: nil
    }
  end
end
