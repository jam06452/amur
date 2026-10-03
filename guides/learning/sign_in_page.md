# Sign-in page

Amur ships an optional sign-in page that lists every configured provider and
links each one to `/auth/:provider`. It is served by `Amur.Router` from Amur's
own `priv/` directory, so it works in Phoenix and in a standalone
`Plug.Router` without copying any files into your application.

## Enabling the page

The page is available as soon as `Amur.Router` is mounted — no extra setup is
needed. Mount the router as described in [Installation](installation.html):

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

Visit `/auth` to see it.

The Igniter installer's `--page` flag records the application name shown in the
heading, but the page itself is always served:

```bash
mix igniter.install amur --provider github,google,discord --page
```

## Behaviour

- The page lists every provider configured under `:amur, :providers`, in the
  order they are declared.
- Each provider is rendered as a button linking to `/auth/:provider`.
- Provider icons are inlined as SVG with `fill="currentColor"`, so they follow
  the page's text colour and stay visible in dark mode.
- When no provider is configured, the page responds with `404` rather than
  rendering an empty list:

  ```
  No Amur providers are configured.
  ```

- Asset and provider links are built from the mount point recorded in
  `conn.script_name`, so the page works wherever `Amur.Router` is mounted rather
  than assuming `/auth`.

## Heading

The heading reads "Sign in to *name*". Set the name with `:app_name`:

```elixir
config :amur,
  app_name: "MyApp"
```

When unset, the heading reads "Sign in to your account".

## Logo

By default the page shows the first configured provider's icon. Supply your own
logo with the `:logo` key, in any of these forms.

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

A missing or unreadable file falls back to the provider icon rather than failing
the page. Inline SVG inherits the page's text colour, so it adapts to light and
dark mode automatically.

The fallback provider icon is the first configured provider that has one, which
includes a custom provider's [`logo/0`](custom_providers.html#logo0-optional)
when it is implemented.

## Assets

The page's CSS and the bundled provider icons are served from Amur's
`priv/static` directory by `Amur.Page.asset/2`. Only files that exist in that
directory are served, so a request cannot escape it. Requests for assets that
don't exist fall through to the host router.

Each built-in provider has a bundled icon at `priv/static/<provider>.svg`. A
custom provider has none unless it implements `logo/0`.

## Without the page

If you'd rather build your own UI, you don't need the page at all. Link users
directly to `/auth/:provider` for each provider you want to offer, and Amur
handles the rest. The page is purely a convenience.
