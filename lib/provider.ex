defmodule Amur.Provider do
  @moduledoc """
  Behaviour for defining custom OAuth providers.

  ## Example

      defmodule MyApp.Auth.Discord do
        use Amur.Provider

        def strategy, do: Assent.Strategy.OAuth2

        def base_config do
          [
            base_url: "https://discord.com/api",
            authorization_endpoint: "/oauth2/authorize",
            token_endpoint: "/oauth2/token",
            user_endpoint: "/users/@me"
          ]
        end

        def normalize_user(user) do
          %{uid: user["id"], email: user["email"], name: user["username"]}
        end
      end
  """

  @callback strategy() :: module()
  @callback base_config() :: keyword()
  @callback normalize_user(map()) :: map()

  @doc """
  Marks the using module as an `Amur.Provider` implementation.

  This macro registers the behaviour callbacks without adding runtime
  functions, allowing the module to define its provider-specific strategy,
  configuration, and user normalization.
  """
  defmacro __using__(_) do
    quote do
      @behaviour Amur.Provider
    end
  end
end
