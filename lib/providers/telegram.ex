defmodule Amur.Providers.Telegram do
  @moduledoc """
  Telegram OAuth provider for Amur.

  Wraps `Assent.Strategy.Telegram`, which authenticates via the Telegram Login
  Widget rather than a standard OAuth redirect.

  ## Configuration

  `base_config/0` is empty: Telegram requires `bot_token`, `origin`, and
  `return_to` to be supplied at runtime, so everything comes from your config.

  Sets no default scope.

  ## Normalized user

  Maps `sub` to `:uid` and `picture` to `:avatar`. For `:name` it joins
  `given_name` and `family_name` (dropping any blank parts), falling back to
  `preferred_username` when neither is present. Telegram returns no email, so
  that key is omitted.
  """

  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.Telegram

  @impl true
  def base_config do
    []
  end

  @impl true
  def normalize_user(user) do
    given_name = user["given_name"]
    family_name = user["family_name"]

    name =
      if given_name || family_name do
        [given_name, family_name]
        |> Enum.filter(&(&1 not in [nil, ""]))
        |> Enum.join(" ")
      else
        user["preferred_username"]
      end

    %{
      uid: user["sub"],
      name: name,
      avatar: user["picture"]
    }
  end
end
