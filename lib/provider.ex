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

  defmacro __using__(_) do
    quote do
      @behaviour Amur.Provider
    end
  end
end
