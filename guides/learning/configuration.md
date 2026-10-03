# Configuration

All of Amur's configuration lives under the `:amur` application environment.
It is normally set in `config/runtime.exs`, since credentials come from the
environment.

```elixir
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

## Keys

| Key | Required | Description |
|---|---|---|
| `base_url` | no | Base URL used to build the `redirect_uri` (`#{base_url}/auth/:provider/callback`). Defaults to `""`. |
| `providers` | yes | Keyword list of provider configurations. Each key is a provider name, each value is either a keyword list of credentials or a custom provider module. |
| `app_name` | no | Name shown in the sign-in page heading. Defaults to `"your account"`. |
| `logo` | no | Logo shown above the heading: `{:path, url}`, `{:file, path}`, `{:svg, markup}`, or a bare string. See [Logo](sign_in_page.html#logo). Defaults to the first provider's icon. |
| `on_success` | yes | A `{module, function, args}` MFA tuple or a function capture of arity 2, called with `(conn, %{user: normalized_user, token: token})`. |
| `on_failure` | no | Same format as `on_success`, called with `(conn, reason)`. Defaults to a redirect to `/`. |

## `:base_url`

`:base_url` is the only thing that determines the redirect URI Amur sends to
the provider:

```
#{base_url}/auth/#{provider}/callback
```

It must match the callback URL you registered with the provider, including
scheme, host, port, and any path prefix. In development this is usually
`http://localhost:4000`; in production it is your public origin.

If `:base_url` is left at its default of `""`, the redirect URI becomes a
relative path like `/auth/github/callback`, which providers will reject.

## `:providers`

`:providers` is a keyword list. The order matters: the sign-in page lists
providers in the order they are declared, and the first provider with an icon
supplies the page's fallback logo.

Each value is either:

- a **keyword list of credentials** for a built-in provider, or
- a **module** implementing `Amur.Provider` for a custom provider.

```elixir
config :amur,
  providers: [
    github: [client_id: "..", client_secret: ".."],   # built-in
    acme: MyApp.Auth.AcmeProvider                      # custom
  ]
```

Credentials are merged over the provider's `base_config/0`, so you only supply
what differs. The `:scopes` key is special-cased and written into the strategy's
authorization params. See [Providers](providers.html) for details.

## `:on_success`

`:on_success` is required. It is called with the connection and a map
containing the normalized `:user` and the OAuth `:token`:

```elixir
config :amur,
  on_success: &MyAppWeb.AuthController.on_success/2
```

The callback must return a `Plug.Conn`. Bind only what you need:

```elixir
def on_success(conn, %{user: user}) do
  # ignore the token
end

def on_success(conn, %{user: user, token: token}) do
  # use the token to call the provider's API
end
```

The token map's keys depend on the provider's flow. OAuth 2.0 providers use
`token["access_token"]`; OAuth 1.0 (Twitter) uses `token["oauth_token"]` and
`token["oauth_token_secret"]`.

## `:on_failure`

`:on_failure` is optional and defaults to redirecting to `/`. It is called with
the connection and a reason:

```elixir
config :amur,
  on_failure: &MyAppWeb.AuthController.on_failure/2
```

Reasons include `:unknown_provider`, `:invalid_session_params`, and whatever the
Assent strategy returns when an OAuth operation fails.

## `:app_name`

The name shown in the sign-in page heading:

```elixir
config :amur,
  app_name: "MyApp"
```

When unset, the heading reads "Sign in to your account".

## `:logo`

The logo shown above the heading. See [Sign-in page](sign_in_page.html#logo) for
the accepted forms.

## MFA tuples

Both callbacks accept an MFA tuple instead of a function capture:

```elixir
config :amur,
  on_success: {MyAppWeb.AuthController, :on_success, []}
```

A function capture is usually clearer and is what the Igniter installer
generates.

## Environment variables

The Igniter installer reads credentials from environment variables named after
each provider:

```
GITHUB_CLIENT_ID=<ID>
GITHUB_CLIENT_SECRET=<SECRET>
```

The prefix is the uppercased provider atom. `digital_ocean` becomes
`DIGITAL_OCEAN_CLIENT_ID`, `azure_ad` becomes `AZURE_AD_CLIENT_ID`, and so on.

The installer also adds a small `.env` loader to `config/runtime.exs` so local
development picks up a `.env` file without extra tooling. It is skipped in the
test environment.
