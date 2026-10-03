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

        # Optional: shown on the sign-in page. Omit to render no icon.
        def logo, do: {:file, "priv/static/images/discord.svg"}
      end
  """

  @callback strategy() :: module()
  @callback base_config() :: keyword()
  @callback normalize_user(map()) :: map()
  @callback logo() :: Amur.Provider.logo() | :error

  @typedoc """
  A provider logo, in any of the forms accepted by the `:logo` configuration.

    * `{:svg, markup}` - inline SVG markup, rendered as-is
    * `{:file, path}` - a local SVG file, read and inlined
    * `{:path, url}` - a URL served by the host application
    * a bare string - a local file when one exists at that path, otherwise a URL

  Returning `:error` (the default) means the provider has no logo of its own.
  """
  @type logo :: {:svg, String.t()} | {:file, String.t()} | {:path, String.t()} | String.t()

  @doc """
  Marks the using module as an `Amur.Provider` implementation.

  This macro registers the behaviour callbacks without adding runtime
  functions, allowing the module to define its provider-specific strategy,
  configuration, and user normalization.

  It also provides a default `logo/0` that returns `:error`, so a provider
  without a bundled icon falls back to the sign-in page's default. Override
  `logo/0` to give a custom provider its own icon on the sign-in page.
  """
  defmacro __using__(_) do
    quote do
      @behaviour Amur.Provider

      @impl Amur.Provider
      def logo, do: :error

      defoverridable logo: 0
    end
  end
end
