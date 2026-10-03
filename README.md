
# Amur - OAuth 2.0 and OAuth 1.0 for Elixir Plug and Phoenix

[![Hex.pm](https://img.shields.io/hexpm/v/amur.svg)](https://hex.pm/packages/amur)
[![Hex Docs](https://img.shields.io/badge/hex-docs-8e44ad.svg)](https://hexdocs.pm/amur)

Amur is an Elixir OAuth client and authentication library for
[Plug](https://hexdocs.pm/plug) and Phoenix applications.

It provides a small, provider-agnostic OAuth login flow without requiring
Phoenix. Amur handles the OAuth handshake, state protection,
[PKCE](https://auth0.com/docs/get-started/authentication-and-authorization-flow/authorization-code-flow-with-pkce),
provider-specific configuration, and user normalization while leaving
authentication and user data management up to your application.

- Plug-native, works with Phoenix or standalone Plug
- State & PKCE, handled automatically
- Stateless by default, temporary OAuth state is cleared from session after the callback
- 24 built-in [providers](#built-in-providers)
- Normalized users, the same data format across providers
- Custom providers, add providers that aren't built in
- Igniter, get started in under 60 seconds
- Built on Assent, OAuth strategies are provided by [Assent](https://hex.pm/packages/assent)

## Why Amur?

Amur sits between your router and your OAuth provider:

<p align="center">
  <img alt="Amur OAuth flow" src="https://raw.githubusercontent.com/jam06452/amur/main/assets/flow.svg" width="202">
</p>

Amur doesn't create users, manage sessions or impose any authentication systems on your application. It gives you the OAuth result and you decide what happens next.

## Quick Start - [Igniter](https://igniter.hexdocs.pm/readme.html) (Recommended)

```elixir
def deps do
  [
    {:igniter, "~> 0.8"}
  ]
end
```

```bash
# Defaults to GitHub
mix igniter.install amur --provider <Your Provider>
```
```bash
# Configure multiple providers
mix igniter.install amur --provider github,google
```
```bash
# Also generate a sign-in page at /auth
mix igniter.install amur --provider google,github,discord --page
```

Options:

| Flag | Description |
|---|---|
| `--provider <name>` | Provider atom used in the generated config (default: `github`), look here for the list of [providers](#built-in-providers) |
| `--all` | Generate config for every built-in provider (cannot be combined with `--provider`) |
| `--page` | Serve a sign-in page listing the configured providers at `/auth` |
| `--app <name>` | Override the detected app name |
| `--no-config` / `--no-router` / `--no-controller` | Skip individual pieces |

Add your secrets into a .env:

```
GITHUB_CLIENT_ID=<ID>
GITHUB_CLIENT_SECRET=<SECRET>
```

That's it for basic setup of Amur.

## Adding the sign-in page to an existing project

If Amur is already installed and you only want the sign-in page, re-run the
installer with `--page`. The task is additive: it merges new providers into your
existing configuration and leaves files it already generated untouched.

```bash
mix igniter.install amur --provider github,google,discord --page
```

Running it again is safe. The installer detects an existing Amur mount and does
not add a second `forward` to your router, and it skips the auth controller when
one is already present:

```
[skip] MyAppWeb.Router already forwards to Amur.Router; leaving unchanged.
[skip] lib/my_app_web/controllers/auth_controller.ex already exists; leaving unchanged.
```

Providers are merged rather than replaced, so adding one does not drop the
credentials already configured:

```elixir
config :amur,
  providers: [
    github: [...],   # kept
    google: [...],   # added
    discord: [...]   # added
  ],
  app_name: "MyApp"  # added by --page
```

### Page only, no other changes

To add just the page to a project that is already configured, skip the pieces
you do not want regenerated:

```bash
mix igniter.install amur --page --no-router --no-controller
```

`--no-router` and `--no-controller` leave your existing router and controller
alone, while `--page` still records the application name used in the heading.

### Without Igniter

The page is served by `Amur.Router` from Amur's own `priv/` directory, so no
files need to be copied into your application. If you mount the router manually,
the page is available as soon as the router is mounted:

```elixir
# Phoenix
scope "/auth", alias: false do
  pipe_through :browser
  forward "/", Amur.Router
end
```

```elixir
# Plug
forward "/auth", to: Amur.Router
```

Then set the name shown in the heading:

```elixir
config :amur,
  app_name: "MyApp"
```

Visit `/auth` to see the page. See [Sign-in page](#sign-in-page) for the logo and
heading options.

## Built-in providers

Amur ships with support for the following providers:

- [Apple](https://developer.apple.com/documentation/signinwithapple),
- [Auth0](https://auth0.com/docs/get-started/auth0-overview/create-applications)
- [Azure AD](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)
- [Basecamp](https://github.com/basecamp/bc3-api/blob/master/sections/authentication.md)
- [Bitbucket](https://support.atlassian.com/bitbucket-cloud/docs/use-oauth-on-bitbucket-cloud/)
- [DigitalOcean](https://docs.digitalocean.com/reference/api/oauth/)
- [Discord](https://discord.com/developers/docs/topics/oauth2)
- [Facebook](https://developers.facebook.com/documentation/facebook-login)
- [GitHub](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)
- [GitLab](https://docs.gitlab.com/ee/integration/oauth_provider.html)
- [Google](https://developers.google.com/identity/protocols/oauth2)
- [Hack Club](https://auth.hackclub.com/docs/oauth-guide)
- [Instagram](https://developers.facebook.com/docs/instagram-basic-display-api/getting-started)
- [LINE](https://developers.line.biz/en/docs/line-login/integrate-line-login/)
- [LinkedIn](https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2)
- [Slack](https://api.slack.com/authentication/oauth-v2)
- [Spotify](https://developer.spotify.com/documentation/web-api/concepts/authorization)
- [Strava](https://developers.strava.com/docs/authentication/)
- [Stripe](https://docs.stripe.com/stripe-apps/api-authentication/oauth)
- [Telegram](https://core.telegram.org/widgets/login)
- [Twitch](https://dev.twitch.tv/docs/authentication/)
- [Twitter (X)](https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code)
- [VK](https://docs.strapi.io/cms/configurations/users-and-permissions-providers/vk)
- [Zitadel](https://zitadel.com/docs/examples/identity-proxy/oauth2-proxy)




Each is a thin wrapper around the corresponding [Assent](https://github.com/pow-auth/assent) strategy.

## Custom providers

You can define your own provider module using the `Amur.Provider` behaviour:

```elixir
defmodule MyApp.Auth.CustomProvider do
  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.OAuth2

  @impl true
  def base_config do
    [
      base_url: "https://api.example.com",
      authorization_endpoint: "/oauth/authorize",
      token_endpoint: "/oauth/token",
      user_endpoint: "/user"
    ]
  end

  @impl true
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

When the default scope isn't fit for your needs you can use a custom scope to get exactly whats needed. To request specific OAuth scopes, pass them in your provider config:

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

## Manual Setup

This is what igniter sets up for you automatically.

### 1. Configure your OAuth providers

```elixir
# config/runtime.exs
config :amur,
  base_url: System.get_env("BASE_URL") || "http://localhost:4000",
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
| `app_name` | no | Name shown in the sign-in page heading. Defaults to `"your account"`. |
| `logo` | no | Logo shown above the heading: `{:path, url}`, `{:file, path}`, `{:svg, markup}`, or a bare string. See [Logo](#logo). Defaults to the first provider's icon. |
| `on_success` | yes | A `{module, function, args}` MFA tuple or a function capture of arity 2, called with `(conn, %{user: normalized_user, token: token})`. |
| `on_failure` | no | Same format as `on_success`, called with `(conn, reason)`. Defaults to a redirect to `/`. |

### 2. Mount the router

```elixir
# Phoenix
scope "/auth", alias: false do
  pipe_through :browser
  forward "/", Amur.Router
end
```

The `alias: false` on the scope is required, without it Phoenix rewrites `Amur.Router` as `YourAppWeb.Amur.Router`.

Inside a browser pipeline, session and flash helpers are available for your callbacks.

Amur works with `Plug.Router` too:

```elixir
# Plug
forward "/auth", to: Amur.Router
```

The router exposes three endpoints:

| Endpoint | Description |
|---|---|
| `GET /auth` | Sign-in page listing the configured providers |
| `GET /auth/:provider` | Initiates the OAuth flow |
| `GET /auth/:provider/callback` | Handles the provider callback |

Amur stores the OAuth handshake params (the `state`, PKCE verifier, ...) in
the session for the duration of the flow and clears them automatically once
the callback has been handled, no manual cleanup needed.

### Sign-in page

The sign-in page is served by `Amur.Router` from Amur's own `priv/` directory,
so it works in Phoenix and in a standalone `Plug.Router` without copying any
files into your application. It lists every provider configured under
`:amur, :providers` and links each one to `/auth/:provider`.

Passing `--page` to the installer records the application name shown in the
page heading:

```elixir
config :amur,
  app_name: "MyApp"
```

When no provider is configured the page responds with `404` rather than
rendering an empty list.

### Logo

By default the page shows the first configured provider's icon. Supply your own
logo with the `:logo` key, in any of these forms:

A path to an image your application serves:

```elixir
config :amur,
  logo: {:path, "/images/logo.svg"}
```

A local SVG file, which is read and inlined so the page needs no extra request:

```elixir
config :amur,
  logo: {:file, "priv/static/images/logo.svg"}
```

Inline SVG markup:

```elixir
config :amur,
  logo: {:svg, """
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor">
    <circle cx="12" cy="12" r="10" />
  </svg>
  """}
```

A bare string is resolved automatically: it is read as a local file when one
exists at that path, and treated as a URL otherwise. So both of these work:

```elixir
config :amur, logo: "priv/static/images/logo.svg"  # inlined
config :amur, logo: "/images/logo.svg"             # served by your app
```

A missing or unreadable file falls back to the provider icon rather than
failing the page. Inline SVG inherits the page's text colour, so it adapts to
light and dark mode automatically.

### 3. Add an auth controller

Implement the `Amur.Callback` behaviour so both OAuth result handlers are
present and their arguments are type checked:

```elixir
defmodule MyAppWeb.AuthController do
  @behaviour Amur.Callback

  import Plug.Conn
  import Phoenix.Controller

  @impl true
  def on_success(conn, %{user: user}) do
    conn
    |> put_flash(:info, "Logged in as #{user.email}")
    |> redirect(to: "/")
    |> halt()
  end

  @impl true
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

The public `Amur.User.t()` type represents this map. The `:uid`, `:email`,
`:name`, and `:avatar` fields are optional because providers may not return
them, and provider-specific fields may also be present.

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

The token map's keys depend on the provider's flow: OAuth 2.0 providers use
`token["access_token"]`, while OAuth 1.0 (Twitter) uses `token["oauth_token"]`
and `token["oauth_token_secret"]`.

## License

MIT
