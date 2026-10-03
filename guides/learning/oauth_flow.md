# The OAuth flow

Amur exposes three endpoints and two callbacks. This guide walks through what
happens between them.

## Endpoints

`Amur.Router` exposes these routes, relative to its mount point:

| Endpoint | Description |
|---|---|
| `GET /auth` | Sign-in page listing the configured providers |
| `GET /auth/:provider` | Initiates the OAuth flow |
| `GET /auth/:provider/callback` | Handles the provider callback |

Mounted with `forward "/auth", Amur.Router`, the full paths are
`/auth`, `/auth/:provider`, and `/auth/:provider/callback`. The sign-in page and
its assets are served from Amur's own `priv/` directory, so the same routes work
in Phoenix and in a standalone `Plug.Router` without copying any files into the
host application.

Requests that don't match a route pass through unchanged, so Amur's router can
be mounted alongside your own routes without swallowing them.

## Step 1 — Starting the flow

A request to `GET /auth/:provider` is dispatched to
`Amur.Controller.request/2`. It:

1. Resolves the provider name against the configured providers. Unknown names
   return `{:error, :unknown_provider}`.
2. Asks the provider's Assent strategy for an authorization URL.
3. Stores the returned session parameters — the `state`, the PKCE verifier, and
   anything else that must survive until the callback — in the Plug session
   under `:amur_session_params`.
4. Redirects the user to the provider and halts the connection.

If any step fails, your `:on_failure` callback is invoked instead.

## Step 2 — The provider authenticates the user

The user signs in at the provider and is redirected back to
`GET /auth/:provider/callback`. Most providers send the result as query
parameters; Apple and Azure AD use `response_mode: "form_post"` and send it as a
`POST` body. Amur merges both into `conn.params` before dispatching, so the
callback works either way.

## Step 3 — Completing the flow

`Amur.Controller.callback/2`:

1. Reads `:amur_session_params` from the session and **immediately deletes it**,
   so the handshake state is single-use.
2. Validates that the session parameters contain a non-empty `state`. Missing,
   empty, or malformed state returns `{:error, :invalid_session_params}`.
3. Passes the session parameters and the callback parameters to the provider's
   Assent strategy, which exchanges the code for a token and fetches the user.
4. Normalizes the provider's user response with the provider module's
   `normalize_user/1` and adds the `:provider` key.
5. Invokes your `:on_success` callback with `(conn, %{user: user, token: token})`.

## State and PKCE

Amur stores the OAuth handshake parameters in the session for the duration of
the flow and clears them automatically once the callback has been handled. There
is no manual cleanup and no server-side store.

This means:

- The session must be available on both the request and the callback. Mount the
  router inside a pipeline that fetches the session (Phoenix's `:browser`
  pipeline does this).
- The `state` value is validated on the callback, which is what protects against
  CSRF on the redirect.
- PKCE is handled by the underlying Assent strategy. Providers that require it
  (such as Zitadel) enable it in their `base_config/0`; you can also request it
  per provider.

## The callbacks

Implement both callbacks in the module configured by `:on_success` and
`:on_failure`. The `Amur.Callback` behaviour type-checks their arguments:

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

Both callbacks must return a `Plug.Conn`. Halting is recommended so later plugs
do not modify the response or attempt to send a second one.

## The normalized user

The `user` map passed to `:on_success` has this shape:

```elixir
%{
  provider: "github",      # the provider atom as a string
  uid: "12345",            # provider-specific user ID
  email: "user@example.com",
  name: "username",
  avatar: "https://..."
}
```

The `:uid`, `:email`, `:name`, and `:avatar` fields are optional because
providers may not return them, and provider-specific fields may also be present.
See [Providers](providers.html#normalized-users) for what each provider returns.

## The token

`:on_success` also receives the OAuth `token` in the same map. Bind it only when
you need it, for example to call the provider's API on the user's behalf:

```elixir
def on_success(conn, %{user: user, token: token}) do
  conn
  |> put_session(:access_token, token["access_token"])
  |> redirect(to: "/")
  |> halt()
end
```

The token map's keys depend on the provider's flow:

- OAuth 2.0 providers use `token["access_token"]`.
- OAuth 1.0 (Twitter) uses `token["oauth_token"]` and
  `token["oauth_token_secret"]`.

Amur does not store or refresh tokens. Persisting them is your application's
responsibility.

## Failure reasons

Your `:on_failure` callback receives one of:

| Reason | Cause |
|---|---|
| `:unknown_provider` | The provider name in the URL is not configured, or does not resolve to a built-in or custom provider. |
| `:invalid_session_params` | The session had no handshake state, or the state was empty or malformed. |
| strategy error | Whatever the Assent strategy returned when the token exchange or user fetch failed. |

The default failure handler redirects to `/`.
