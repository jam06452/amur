# Comparisons

Amur is not the only way to do OAuth in Elixir. This guide compares it with the
libraries you are most likely to weigh it against, so you can pick the right tool
for your application.

The short version: Amur is a thin, Plug-native layer over
[Assent](https://hex.pm/packages/assent). It does the OAuth handshake and hands
you a normalized user, and nothing else. If you want a full authentication
system with users, sessions, and password hashing, a library like
[Pow](https://hex.pm/packages/pow) is a better fit. If you want the largest
ecosystem of community strategies, [Überauth](https://hex.pm/packages/ueberauth)
has it.

## At a glance

| | Amur | Assent | Überauth | Pow / PowAssent |
|---|---|---|---|---|
| **Scope** | OAuth handshake + Plug integration | OAuth protocol only | OAuth handshake + Plug integration | Full authentication system |
| **Plug-native** | Yes | No (library, no router) | Yes (a plug) | Yes |
| **Phoenix required** | No | No | No | No, but Phoenix-oriented |
| **Providers built in** | 24 | 23 + 3 base strategies | 1 core, ~125 strategy packages | Via Assent |
| **Provider packaging** | One library | One library | Separate package per provider | One library |
| **Normalized user** | Amur's flat map | OIDC standard claims | `Ueberauth.Auth` struct | Pow's user schema |
| **Creates users** | No | No | No | Yes |
| **Manages sessions** | No | No | No | Yes |
| **Database** | None | None | None | Required |
| **State & PKCE** | Handled for you | You wire it up | Per strategy | Handled |
| **Sign-in page** | Bundled (optional) | No | No | No |
| **Igniter installer** | Yes | No | No | No |

## Amur vs. Assent

Amur is built on Assent, so this is less a competition than a division of labour.

[Assent](https://hex.pm/packages/assent) is a **multi-provider authentication
framework**. It implements the OAuth 1.0a, OAuth 2.0, and OIDC protocol work and
ships a strategy per provider. It is deliberately not a web framework
integration: it has no router, no plugs, and no opinion about where you store the
handshake state. The Assent README shows you writing the `request` and `callback`
handlers yourself, storing `session_params` in the session, and deleting them on
the way back.

Amur does exactly that wiring for you, once, generically:

- **Routing.** Assent leaves you to define the request and callback routes.
  Amur's `Amur.Router` exposes `GET /auth/:provider` and
  `GET /auth/:provider/callback` for every configured provider.
- **Session handling.** Assent returns `session_params` and expects you to store
  and later delete them. Amur stores them under `:amur_session_params` and clears
  them automatically on the callback, so the handshake state is single-use.
- **Multi-provider dispatch.** With Assent you write a module that looks up the
  strategy for a provider name. Amur resolves the provider from the URL for you.
- **User normalization.** Assent normalizes to the
  [OIDC standard claims](https://openid.net/specs/openid-connect-core-1_0.html#rfc.section.5.1)
  shape (`"sub"`, `"email"`, …). Amur normalizes to its own flat map with
  `:provider`, `:uid`, `:email`, `:name`, and `:avatar`, which is easier to
  pattern-match in a callback.
- **A sign-in page.** Assent has none. Amur ships an optional one.

If you are already comfortable writing the Assent glue, or you need to drive the
protocol in a way Amur's router does not expose, use Assent directly. If you want
the same protocol work with the Plug plumbing already done, use Amur. Because
Amur is a thin wrapper, you can also drop down to Assent at any point — every
provider module exposes its `strategy/0`, and any Assent option can be passed
through the provider's config.

## Amur vs. Überauth

[Überauth](https://hex.pm/packages/ueberauth) is the closest thing to a direct
alternative, and the comparison is mostly about packaging and data shape.

Überauth is a **two-phase authentication framework** (request and callback)
implemented as a plug, heavily inspired by Ruby's OmniAuth. The core package
ships almost no providers: each provider lives in its own `ueberauth_*` package,
of which there are around 125 on Hex. You add `{:ueberauth, "~> 0.10"}` plus one
dependency per provider, and configure them as
`provider: {StrategyModule, opts}`.

The differences that matter in practice:

- **One dependency vs. many.** Amur bundles 24 providers in a single library, so
  adding a provider is a config change, not a new dependency. Überauth's
  per-provider packages mean you track a version per provider, and their
  maintenance varies — several popular strategies have not been updated in years.
- **Provider coverage.** Überauth's ecosystem is wider overall (Okta, Cognito,
  Keycloak, CAS, SAML-adjacent strategies, and more), because anyone can publish
  a strategy. Amur covers the 24 most common providers and lets you add the rest
  with the `Amur.Provider` behaviour.
- **User shape.** Überauth hands you a `%Ueberauth.Auth{}` struct with nested
  `info`, `credentials`, and `extra` fields, assigned to `conn.assigns.ueberauth_auth`.
  Amur hands you a flat map passed straight to your `:on_success` callback.
- **Configuration.** Überauth configures providers under
  `config :ueberauth, Ueberauth, providers: [...]`. Amur uses
  `config :amur, providers: [...]` and merges your credentials over each
  provider's defaults.
- **Sign-in page.** Überauth has none; you build the UI. Amur ships an optional
  one.

Both are stateless with respect to users: neither creates accounts or manages
sessions. Überauth is the safer choice if you need a provider Amur does not ship
and one of the community strategies already covers it. Amur is the simpler choice
if your providers are in the built-in set and you would rather not manage a
dependency per provider.

## Amur vs. Pow and PowAssent

[Pow](https://hex.pm/packages/pow) is a **full authentication system** for
Phoenix and Plug, and [PowAssent](https://hex.pm/packages/pow_assent) adds
multi-provider OAuth support on top of it. This is a different category of tool.

Pow owns the whole problem: it generates user schemas, stores users in your
database, hashes passwords, manages sessions and remember-me cookies, and
provides controllers, views, and templates. PowAssent plugs OAuth providers into
that system, using Assent under the hood — the same protocol layer Amur uses.

Choose Pow when you want an authentication system out of the box: user records,
password login, and OAuth all managed for you. Choose Amur when you already have
your own user model, or want to keep authentication decisions in your application
and only need the OAuth handshake solved.

The trade-off is control versus convenience:

- **Pow** requires a database and adopts its conventions for users and sessions.
  You get a lot for free, but you also take on its schema and its upgrade path.
- **Amur** has no database, no schema, and no session management. It gives you the
  normalized user and the token, and you decide what to do with them. That is
  less to learn and less to undo if your needs change, but you write the
  user-creation and session code yourself.

If you are starting a Phoenix app and want "just add login", Pow is the shorter
path. If you have an existing user table, a custom session strategy, or an API
that only needs the OAuth result, Amur stays out of your way.

## Amur vs. Guardian

[Guardian](https://hex.pm/packages/guardian) is a **token-based authentication
library** (JWT and similar). It is not an OAuth client and does not compete with
Amur: it solves what happens *after* a user is authenticated — issuing and
verifying tokens on each request.

The two are complementary. A common setup is Amur for the OAuth handshake and
Guardian for the session token you issue once `:on_success` fires. Überauth's own
documentation makes the same point about pairing with Guardian.

## When to use Amur

Amur is a good fit when:

- you want OAuth login in a Plug or Phoenix app **without** adopting a full
  authentication system,
- your providers are among the 24 built in, or you are happy to define a custom
  provider module,
- you want state and PKCE handled for you, with no server-side store,
- you want a normalized user map and the raw token, and you will handle user
  creation and sessions yourself,
- you want a bundled sign-in page and an Igniter installer to get started fast.

Consider an alternative when:

- you need a provider that only Überauth's ecosystem covers — use Überauth,
- you want users, passwords, and sessions managed for you — use Pow,
- you need to drive the OAuth protocol in ways Amur's router does not expose —
  use Assent directly,
- you need request-time token verification — add Guardian alongside Amur.

## A note on the shared foundation

Amur, PowAssent, and several Überauth strategies all build on Assent, and Amur
and Überauth both follow the OmniAuth-style request/callback model. The libraries
differ in how much they do around that core, not in the protocol underneath. That
means moving between them is mostly a matter of changing the integration layer,
and the OAuth behaviour you rely on is the same battle-tested code either way.
