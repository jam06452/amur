# Overview

Amur is an Elixir OAuth client and authentication library for
[Plug](https://hexdocs.pm/plug) and Phoenix applications. It handles the OAuth
handshake, state protection, [PKCE](https://auth0.com/docs/get-started/authentication-and-authorization-flow/authorization-code-flow-with-pkce),
provider-specific configuration, and user normalization, while leaving
authentication and user data management up to your application.

Amur is built on [Assent](https://hex.pm/packages/assent): every provider is a
thin wrapper around an Assent strategy, so the OAuth protocol work is done by a
battle-tested library and Amur focuses on the Plug integration.

## What Amur does

- **Plug-native** — works with Phoenix or a standalone `Plug.Router`, with no
  Phoenix dependency.
- **State and PKCE, handled automatically** — the OAuth handshake parameters are
  stored in the session and cleared once the callback completes.
- **Stateless by default** — Amur keeps no database, no ETS table, and no
  background processes. The only state is the short-lived session entry for the
  in-flight handshake.
- **24 built-in providers** — see [Providers](providers.html) for the full list.
- **Normalized users** — the same map shape across every provider, with
  provider-specific fields passed through.
- **Custom providers** — add any OAuth 2.0 or OAuth 1.0 provider that isn't
  built in.
- **Telemetry** — observe the OAuth flow with `:telemetry`, without Amur taking
  on any state or imposing a logging strategy.
- **Igniter installer** — get started in under 60 seconds.

## What Amur does not do

Amur is deliberately small. It does **not**:

- create users, manage sessions, or impose an authentication system,
- store tokens or refresh them for you,
- provide authorization or role checks,
- render anything beyond the optional sign-in page.

It gives you the OAuth result and you decide what happens next.

## How it fits together

Amur sits between your router and your OAuth provider:

<p align="center">
  <img alt="Amur OAuth flow" src="https://raw.githubusercontent.com/jam06452/amur/main/assets/flow.svg" width="202">
</p>

The flow has four steps:

1. A user visits `GET /auth/:provider`. `Amur.Router` dispatches to
   `Amur.Controller.request/2`.
2. The controller resolves the provider through Amur's internal config module,
   asks the provider's Assent strategy for an authorization URL, stores the
   handshake parameters (the `state`, PKCE verifier, …) in the session, and
   redirects the user to the provider.
3. The provider authenticates the user and redirects back to
   `GET /auth/:provider/callback`.
4. `Amur.Controller.callback/2` consumes the session parameters, exchanges the
   callback for a token, normalizes the provider's user response, and invokes
   your `:on_success` callback.

If anything fails along the way, your `:on_failure` callback is invoked instead.

## The modules

| Module | Role |
|---|---|
| `Amur.Router` | A Plug router that exposes the three OAuth endpoints. Mount it in your application. |
| `Amur.Controller` | Coordinates the provider-facing part of the flow: authorization requests and callbacks. |
| `Amur.Provider` | The behaviour for defining custom providers. |
| `Amur.Callback` | The behaviour for handling the result of a flow (`on_success/2`, `on_failure/2`). |
| `Amur.User` | The type of the normalized user passed to your callbacks. |
| `Amur.Page` | Renders the optional sign-in page and serves its assets. |
| `Amur.Telemetry.Events` | Documents the `:telemetry` events emitted by the OAuth flow. |
| `Amur.Providers.*` | The built-in provider modules. |

## Where to go next

- [Installation](installation.html) — install Amur with Igniter or manually.
- [Providers](providers.html) — every built-in provider, its scopes, and the
  user shape it returns.
- [Configuration](configuration.html) — every `config :amur` key.
- [The OAuth flow](oauth_flow.html) — the endpoints, the session, and the
  callbacks in detail.
- [Custom providers](custom_providers.html) — define a provider that isn't built in.
- [Sign-in page](sign_in_page.html) — the bundled page, its logo, and its assets.
- [Telemetry](telemetry.html) — the events emitted by the OAuth flow.
