# Installation

Amur can be installed with [Igniter](https://igniter.hexdocs.pm/readme.html),
which generates the router mount, an auth controller, and runtime configuration
for you, or manually if you prefer to wire everything yourself.

## Requirements

- Elixir `~> 1.15`
- [Plug](https://hex.pm/packages/plug) `>= 0.0.0` (installed as a dependency)
- [Assent](https://hex.pm/packages/assent) `~> 0.3` (installed as a dependency)

Amur works with Phoenix and with a standalone `Plug.Router`. Phoenix is not a
dependency.

## With Igniter (recommended)

Add Igniter to your dependencies:

```elixir
def deps do
  [
    {:igniter, "~> 0.8"}
  ]
end
```

Then run the installer:

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

### Installer options

| Flag | Description |
|---|---|
| `--provider <name>` | Provider atom used in the generated config (default: `github`). See [Providers](providers.html) for the list. |
| `--all` | Generate config for every built-in provider (cannot be combined with `--provider`). |
| `--page` | Serve a sign-in page listing the configured providers at `/auth`. |
| `--app <name>` | Override the detected app name. |
| `--no-config` / `--no-router` / `--no-controller` | Skip individual pieces. |

The installer is additive and safe to re-run. It detects an existing Amur mount
and does not add a second `forward` to your router, and it skips the auth
controller when one is already present:

```
[skip] MyAppWeb.Router already forwards to Amur.Router; leaving unchanged.
[skip] lib/my_app_web/controllers/auth_controller.ex already exists; leaving unchanged.
```

Providers are merged rather than replaced, so adding one does not drop the
credentials already configured.

### Add your secrets

The installer generates a `.env` loader in `config/runtime.exs` and reads
credentials from environment variables named after each provider. Add them to a
`.env` file:

```
GITHUB_CLIENT_ID=<ID>
GITHUB_CLIENT_SECRET=<SECRET>
```

The variable prefix is the uppercased provider name, so `google` becomes
`GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` and `digital_ocean` becomes
`DIGITAL_OCEAN_CLIENT_ID` / `DIGITAL_OCEAN_CLIENT_SECRET`.

That's it for basic setup of Amur.

## Adding the sign-in page to an existing project

If Amur is already installed and you only want the sign-in page, re-run the
installer with `--page`. The task is additive: it merges new providers into your
existing configuration and leaves files it already generated untouched.

```bash
mix igniter.install amur --provider github,google,discord --page
```

### Page only, no other changes

To add just the page to a project that is already configured, skip the pieces
you do not want regenerated:

```bash
mix igniter.install amur --page --no-router --no-controller
```

`--no-router` and `--no-controller` leave your existing router and controller
alone, while `--page` still records the application name used in the heading.

## Manual setup

This is what Igniter sets up for you automatically.

### 1. Add the dependency

```elixir
def deps do
  [
    {:amur, "~> 0.3"}
  ]
end
```

### 2. Configure your OAuth providers

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

See [Configuration](configuration.html) for every key.

### 3. Mount the router

```elixir
# Phoenix
scope "/auth", alias: false do
  pipe_through :browser
  forward "/", Amur.Router
end
```

The `alias: false` on the scope is required. Without it Phoenix rewrites
`Amur.Router` as `YourAppWeb.Amur.Router`.

Inside a browser pipeline, session and flash helpers are available for your
callbacks.

Amur works with `Plug.Router` too:

```elixir
# Plug
forward "/auth", to: Amur.Router
```

### 4. Add an auth controller

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

### 5. Register the callback URL with your provider

The redirect URI Amur sends is built from `:base_url`:

```
#{base_url}/auth/:provider/callback
```

With `base_url: "http://localhost:4000"` and the `github` provider, register
`http://localhost:4000/auth/github/callback` in your GitHub OAuth app. Every
provider you configure needs its own callback URL registered.

## Verifying the installation

Start your application and visit:

- `GET /auth` — the sign-in page, if you passed `--page` or set `:app_name`.
- `GET /auth/:provider` — starts the OAuth flow for a configured provider.

If `/auth` responds with `404 No Amur providers are configured.`, no provider
resolved successfully. Check that `:providers` is set and that each entry names
a built-in provider or a custom provider module.
