defmodule Amur.Providers.GitHub do
  @moduledoc """
  GitHub OAuth provider for Amur.

  Wraps `Assent.Strategy.Github`.

  ## Configuration

  Default scope: `user:email`.

  ## Normalized user

  Maps `sub` to `:uid`, `email` to `:email`, `preferred_username` to `:name`,
  and `picture` to `:avatar`.

  > #### Private email addresses {: .warning}
  >
  > GitHub only returns `email` when the user has a public email address or has
  > granted the `user:email` scope. Users with a private email may come back
  > with `:email` unset, so treat it as optional.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Github

  @impl true
  def base_config do
    [authorization_params: [scope: "user:email"]]
  end

  @impl true
  def normalize_user(user) do
    %{
      uid: user["sub"],
      email: user["email"],
      name: user["preferred_username"],
      avatar: user["picture"]
    }
  end
end
