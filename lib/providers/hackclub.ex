defmodule Amur.Providers.HackClub do
  @moduledoc """
  Hack Club OAuth provider for Amur.

  Uses the generic `Assent.Strategy.OAuth2` strategy pointed at
  `https://auth.hackclub.com`, fetching the user from `/api/v1/me`.

  ## Configuration

  Sends the client secret in the request body
  (`auth_method: :client_secret_post`).

  Default scope: `email slack_id name`.

  ## Normalized user

  This is the one provider that nests its data: the response carries an
  `identity` object, which is where the fields are read from.

    * `identity.id` -> `:uid`
    * `identity.primary_email` -> `:email`
    * `identity.first_name` + `identity.last_name` -> `:name`
    * `identity.slack_id` -> `:slack_id` (a provider-specific extra field)

  No avatar is returned.
  """
  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.OAuth2

  @impl true
  def base_config do
    [
      base_url: "https://auth.hackclub.com",
      authorize_url: "/oauth/authorize",
      token_url: "/oauth/token",
      user_url: "/api/v1/me",
      auth_method: :client_secret_post,
      authorization_params: [scope: "email slack_id name"]
    ]
  end

  @impl true
  def normalize_user(user) do
    identity = user["identity"]

    %{
      uid: identity["id"],
      email: identity["primary_email"],
      name: "#{identity["first_name"]} #{identity["last_name"]}",
      slack_id: identity["slack_id"]
    }
  end
end
