defmodule Amur do
  @moduledoc """
  Simple OAuth for Plug apps.

  ## Setup

  ```elixir
  # mix.exs
  {:amur, "~> 0.2.3"}
  ```

  ## Quickstart with `mix amur.gen`

  Run the generator from your project root to scaffold the controller, mount the
  router, and write the config block automatically:

  ```bash
  mix amur.gen
  ```

  It inspects your `mix.exs` to detect the app name, derives the web module
  (`AppWeb` when a Phoenix-style `lib/<app>_web` layout is present, otherwise
  `App`), and writes the boilerplate for you — no prompts. It defaults to the
  `github` provider.

  Options:

  | Flag | Description |
  |---|---|
  | `--provider <name>` | Provider atom used in the generated config (default: `github`) |
  | `--all` | Generate config for every built-in provider (cannot be combined with `--provider`) |
  | `--app <name>` | Override the detected app name  |
  | `--no-config` / `--no-router` / `--no-controller` | Skip individual pieces |

  ```bash
  mix amur.gen --provider google
  mix amur.gen --all
  ```

  ## Manual setup
  ```elixir
  # config/runtime.exs
  config :amur,
    base_url: "http://localhost:4000",
    providers: [
      github: [
        client_id: System.fetch_env!("GITHUB_CLIENT_ID"),
        client_secret: System.fetch_env!("GITHUB_CLIENT_SECRET")
      ]
    ],
    on_success: &MyAppWeb.AuthController.on_success/2,
    on_failure: &MyAppWeb.AuthController.on_failure/2

  # router.ex
  forward "/auth", Amur.Router
  ```

  Mount `Amur.Router` under `/auth` in your router with `forward "/auth", Amur.Router`.
  In Phoenix, place the forward inside your browser pipeline so session and
  flash helpers are available if your callbacks use them, and use `alias: false`
  on the scope that contains the forward so Phoenix does not rewrite the module
  name. It works with both `Phoenix.Router` and `Plug.Router`. It exposes:

  - `GET /auth/:provider` - start the OAuth flow
  - `GET /auth/:provider/callback`- handle the provider callback

  The OAuth handshake params are kept in the session for the duration of the
  flow and are automatically cleared once the callback has been handled.

  ## `on_success` payload

  `on_success/2` receives a map with two keys:

    * `:user` - the normalized user map (provider-specific fields plus `:provider`)
    * `:token` - the OAuth token returned by the strategy

  Pattern-match only what you need. If you don't need the token, ignore it:

      def on_success(conn, %{user: user}) do
        conn
        |> put_flash(:info, "Logged in as \#{user[:email]}")
        |> redirect(to: "/")
      end

  If you need it (e.g. to call the provider's API on behalf of the user), bind it:

      def on_success(conn, %{user: user, token: token}) do
        conn
        |> put_session(:access_token, token["access_token"])
        |> redirect(to: "/")
      end

  The token's keys depend on the provider's flow: OAuth 2.0 providers (GitHub,
  Google, ...) use `token["access_token"]`, while OAuth 1.0 (Twitter) uses
  `token["oauth_token"]` and `token["oauth_token_secret"]`.
  """
end
