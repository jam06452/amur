# Changelog for Amur

This release adds a built-in sign-in page, gives providers their own icons, and makes the Igniter
installer safe to run more than once. It also restructures the documentation into a published
guides tree, adds a test suite, and tightens the CI pipeline.

## Unified Sign-in Page

Amur now ships an optional sign-in page that lists every configured provider and links each one to
`/auth/:provider`. It is served by `Amur.Router` at the mount point, so there is nothing to wire up
beyond mounting the router:

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

Visit `/auth` to see it. The page is a plain Plug, so it behaves the same in Phoenix and in a
standalone `Plug.Router`, and its template and assets are read from Amur's own `priv/` directory —
no files are copied into the host application.

The heading reads "Sign in to *name*", configured with `:app_name`:

```elixir
config :amur,
  app_name: "MyApp"
```

When unset, the heading reads "Sign in to your account". When no provider is configured, the page
responds with `404` rather than rendering an empty list.

Asset and provider links are built from the mount point recorded in `conn.script_name`, so the page
works wherever `Amur.Router` is mounted rather than assuming `/auth`.

The page is served as a complete HTML document — doctype, `<html lang="en">`, and a `<head>` with a
title and meta description — so it is valid on its own and passes the document-level accessibility
and SEO checks that Lighthouse applies. The page is English-only, and the `lang` attribute reflects
that.

The response also carries a restrictive `Content-Security-Policy` (`default-src 'none'`, no scripts,
no framing) plus `X-Content-Type-Options: nosniff` and `Referrer-Policy: no-referrer`, so the page is
hardened even when the host application sets no security headers of its own.

## Provider Icons

Every built-in provider now has a bundled SVG icon, inlined with `fill="currentColor"` so it follows
the page's text colour and stays visible in dark mode. Custom providers can supply their own icon by
implementing the new optional `logo/0` callback:

```elixir
defmodule MyApp.Auth.MyProvider do
  use Amur.Provider

  @impl Amur.Provider
  def logo, do: {:file, "priv/static/images/my_provider.svg"}
end
```

The callback accepts the same forms as the page-level `:logo` configuration:

- `{:svg, markup}` — inline SVG markup, rendered as-is
- `{:file, path}` — a local SVG file, read and inlined
- `{:path, url}` — a URL served by the host application
- a bare string — a local file when one exists at that path, otherwise a URL

Returning `:error` (the default) means the provider has no logo of its own, and the page falls back
to the first configured provider that has one.

The page itself can be given a logo in the same forms:

```elixir
config :amur,
  logo: {:path, "/images/logo.svg"}
```

A missing or unreadable file falls back to the provider icon rather than failing the page.

## Installer Improvements

The Igniter installer is now safe to re-run on an already-configured project. It detects an existing
`/auth` mount by scope rather than by file contents, so it will not add a second `forward` to the
same router, and it locates the auth controller wherever the project placed it.

A new `--page` flag records the application name shown in the sign-in page heading:

```bash
mix igniter.install amur --provider github,google,discord --page
```

## Documentation

The README content moved into a `guides/` tree and is now published with ExDoc, with `overview` as
the main page:

- `guides/overview.md`
- `guides/introduction/installation.md`
- `guides/learning/providers.md`
- `guides/learning/configuration.md`
- `guides/learning/oauth_flow.md`
- `guides/learning/custom_providers.md`
- `guides/learning/sign_in_page.md`

Package metadata gained a richer description, `source_url`/`source_ref`, canonical and homepage
URLs, and Hex/HexDocs links.

### Changes

- [Page] Serve a sign-in page listing configured providers

  `Amur.Router` now serves a sign-in page at the mount point (`GET /auth`) and its static assets
  alongside the existing `GET /auth/:provider` and `GET /auth/:provider/callback` routes. The page
  and its assets are read from Amur's own `priv/` directory, so the same routes work in Phoenix and
  in a standalone `Plug.Router` without copying any files into the host application.

- [Page] Memoize the rendered sign-in body

  The template was rendered on every request even though its output only changes when the
  configuration does. The rendered body is now cached in `:persistent_term`, keyed on the provider
  list, the resolved provider modules, the application name, and the logo.

  The mount point is deliberately not part of the key: it is substituted into the cached body per
  request, so one render serves every mount point. A configuration change yields a new key and a
  fresh render without a restart.

- [Provider] Add an optional `logo/0` callback

  Providers may now implement `logo/0` to give themselves an icon on the sign-in page. The default
  returns `:error`, so a provider without a bundled icon falls back to the page default. The
  callback accepts `{:svg, markup}`, `{:file, path}`, `{:path, url}`, or a bare string.

- [Config] Add `configured_providers/0`

  Returns the provider names configured for the application, in declaration order, filtered to
  those that resolve to a usable provider. The sign-in page uses it so it never links to a provider
  that would fail.

- [Install] Make the installer safe to re-run

  Re-running the installer in a project that already has an Amur mount no longer adds a second
  `forward` to the same router. Only a `forward "/", Amur.Router` inside the `/auth` scope counts,
  so a project that forwards Amur somewhere else still gets the documented `/auth` mount. The
  installer also locates the auth controller wherever the project placed it, rather than assuming
  the path it generates.

- [Install] Add a `--page` option

  Passing `--page` configures the application name used by the built-in sign-in page, which
  `Amur.Router` serves at the mount point.

- [Mix] Treat compiler warnings as errors

  `elixirc_options: [warnings_as_errors: true]` is now set, so warnings fail the build.

- [Mix] Add a `test.coverage` alias

  `mix test.coverage` runs the suite with coverage.

- [Mix] Add Sobelow to the CI alias

  The `ci` alias now runs `test`, `credo --strict`, `format --check-formatted`, `deps.audit`,
  `dialyzer`, and `sobelow`.

- [Docs] Publish the guides with ExDoc

  The README content moved into a `guides/` tree, with grouped extras and modules, and package
  metadata gained `source_url`, `source_ref`, canonical and homepage URLs, and Hex/HexDocs links.

- [CI] Run `mix ci` on push, pull requests, and a weekly schedule

  A GitHub Actions workflow runs `mix ci` on pushes to `main`, on pull requests, and on a weekly
  schedule to catch advisories and dependency drift against unchanged code.

### Enhancements

- [Page] Inline provider icons and format provider labels

  Provider icons are inlined as SVG with `fill="currentColor"`, and display names are formatted for
  brands that do not title-case cleanly, such as `digital_ocean` to "DigitalOcean" and `hackclub`
  to "Hack Club".

- [Page] Add icons for the remaining built-in providers

  Every built-in provider now has a bundled icon at `priv/static/<provider>.svg`.

- [Test] Add a test suite with 100% coverage

  The published 0.3.4 shipped no tests. This release adds a full suite covering the controller,
  router, config, providers, installer, and the sign-in page, including provider fixtures, hack
  club normalization, and installer edge cases.

  Run `mix test.coverage` to see the report: every module, and the project total, is at 100%.

### Bug Fixes

- [Install] Ignore forwards in nested scopes when detecting the `/auth` mount

  Mount detection now only considers a `forward "/", Amur.Router` inside the `/auth` scope, so a
  nested forward elsewhere does not suppress the documented mount.

- [Install] Warn when the Phoenix router cannot be located

  `phoenix_router_mounted?/2` now returns `:mounted`, `:not_mounted`, or `:not_found` rather than a
  boolean. When the router module cannot be found, the installer emits a warning instead of
  crashing downstream in `has_pipeline/3`.

- [Page] Escape the application name in the sign-in heading

  The configured `:app_name` is escaped before it is rendered into the heading.

- [Page] Stop defaulting the page logo to a provider icon

  The page no longer assumes a provider icon when no logo is configured, and a path-based provider
  logo is kept as an image fallback. The logo wrapper also gets an explicit display mode.

- [Page] Make the Zitadel icon visible on light backgrounds

  The Zitadel icon now renders correctly against light backgrounds.
