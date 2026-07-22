defmodule Amur.Providers.Telegram do
  @moduledoc """
  Telegram OAuth provider for Amur.

  Uses Assent's Telegram strategy, which requires custom configuration:
  `bot_token`, `origin`, and `return_to` must be provided at runtime.
  """

  use Amur.Provider

  def strategy, do: Assent.Strategy.Telegram

  def base_config do
    []
  end

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
