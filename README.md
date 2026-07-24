# Amur

Simple OAuth for Plug apps. Amur gives you a small OAuth callback flow and provider normalization layer. It is Plug-based and does not require Phoenix.

## Installation

Add `amur` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:amur, "~> 0.2"}
  ]
end
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
  | `--app <name>` | Override the detected app name  |
  | `--no-config` / `--no-router` / `--no-controller` | Skip individual pieces |

  ```bash
  mix amur.gen --provider google
  ```
## Setup

### 1. Configure your OAuth providers

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
```

| Key | Required | Description |
|---|---|---|
| `base_url` | no | Base URL used to build the `redirect_uri` (`#{base_url}/auth/:provider/callback`). Defaults to `""`. |
| `providers` | yes | Keyword list of provider configurations. Each key is a provider name, each value is either a keyword list of credentials or a custom provider module. |
| `on_success` | yes | A `{module, function, args}` MFA tuple or a function capture of arity 2, called with `(conn, normalized_user)`. |
| `on_failure` | no | Same format as `on_success`, called with `(conn, reason)`. Defaults to a redirect to `/`. |

### 2. Mount the router

```elixir
# Phoenix
scope "/auth", alias: false do
  pipe_through :browser
  forward "/", Amur.Router
end
```

The `alias: false` on the scope is required — without it Phoenix rewrites `Amur.Router` as `YourAppWeb.Amur.Router`.

Inside a browser pipeline, session and flash helpers are available for your callbacks.

Amur works with `Plug.Router` too:

```elixir
# Plug
forward "/auth", to: Amur.Router
```

The router exposes three endpoints:

| Endpoint | Description |
|---|---|
| `GET /auth/:provider` | Initiates the OAuth flow |
| `GET /auth/:provider/callback` | Handles the provider callback |
| `GET /auth/logout` | Clears Amur's stored session params |

### 3. Add an auth controller

```elixir
defmodule MyAppWeb.AuthController do
  import Plug.Conn
  import Phoenix.Controller

  def on_success(conn, %{user: user}) do
    conn
    |> put_flash(:info, "Logged in as #{user.email}")
    |> redirect(to: "/")
    |> halt()
  end

  def on_failure(conn, reason) do
    conn
    |> put_flash(:error, "Authentication failed")
    |> redirect(to: "/")
    |> halt()
  end
end
```

The normalized `user` map has the following shape:

```elixir
%{
  provider: "github",      # the provider atom as a string
  uid: "12345",            # provider-specific user ID
  email: "user@example.com",
  name: "username",
  avatar: "https://..."
}
```

Different providers may return different fields. See each provider module's `normalize_user/1` for the exact shape.

`on_success/2` also receives the OAuth `token` in the same map. Bind it only
when you need it (for example, to call the provider's API on the user's
behalf); otherwise ignore it by pattern-matching just `:user`:

```elixir
def on_success(conn, %{user: user, token: token}) do
  conn
  |> put_session(:access_token, token["access_token"])
  |> redirect(to: "/")
  |> halt()
end
```

### 4. (Optional) Clear the session on logout

```elixir
# In your own logout handler
Amur.logout(conn)
```

This deletes the `:amur_session_params` key from the session. The `GET /auth/logout` endpoint calls this automatically and redirects to `/`.

## Built-in providers

Amur ships with support for the following providers:

Apple, Auth0, Azure AD, Basecamp, Bitbucket, DigitalOcean, Discord, Facebook, GitHub, GitLab, Google, Hack Club, Instagram, LINE, LinkedIn, Slack, Spotify, Strava, Stripe, Telegram, Twitch, Twitter (X), VK, Zitadel

Each is a thin wrapper around the corresponding [Assent](https://github.com/pow-auth/assent) strategy.

## Custom providers

You can define your own provider module using the `Amur.Provider` behaviour:

```elixir
defmodule MyApp.Auth.CustomProvider do
  use Amur.Provider

  def strategy, do: Assent.Strategy.OAuth2

  def base_config do
    [
      base_url: "https://api.example.com",
      authorization_endpoint: "/oauth/authorize",
      token_endpoint: "/oauth/token",
      user_endpoint: "/user"
    ]
  end

  def normalize_user(user) do
    %{uid: user["id"], email: user["email"], name: user["name"]}
  end
end
```

Then reference it in your config:

```elixir
config :amur,
  providers: [
    my_provider: MyApp.Auth.CustomProvider
  ]
```

## Scopes

To request specific OAuth scopes, pass them in your provider config:

```elixir
config :amur,
  providers: [
    github: [
      client_id: "..",
      client_secret: "..",
      scopes: "user:email,read:org"
    ]
  ]
```

## License

MIT
