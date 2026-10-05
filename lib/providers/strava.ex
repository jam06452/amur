defmodule Amur.Providers.Strava do
  @moduledoc """
  Strava OAuth provider for Amur.

  Wraps `Assent.Strategy.Strava`. Authorization goes to
  `https://www.strava.com/oauth/authorize`, while the athlete is fetched from
  the API at `https://www.strava.com/api/v3/athlete`.

  ## Configuration

  Sends the client secret in the request body
  (`auth_method: :client_secret_post`).

  Default scope: `read_all,profile:read_all`.

  ## Normalized user

  Maps `sub` to `:uid` and `picture` to `:avatar`. For `:name` it prefers
  `preferred_username`, falling back to `given_name` and `family_name` joined
  with a space. Strava returns no email, so that key is omitted.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Strava

  @impl true
  def base_config do
    [
      base_url: "https://www.strava.com/api/v3",
      authorize_url: "https://www.strava.com/oauth/authorize",
      token_url: "/oauth/token",
      user_url: "/athlete",
      authorization_params: [scope: "read_all,profile:read_all"],
      auth_method: :client_secret_post
    ]
  end

  @impl true
  def normalize_user(user) do
    %{
      uid: user["sub"],
      name: user["preferred_username"] || "#{user["given_name"]} #{user["family_name"]}",
      avatar: user["picture"]
    }
  end
end
