# Providers

Amur ships with 24 built-in providers. Each one is a thin wrapper around the
corresponding [Assent](https://github.com/pow-auth/assent) strategy: it supplies
the provider's endpoints and default scopes, and normalizes the provider's user
response into Amur's common shape.

## Built-in providers

| Provider | Atom | Assent strategy | Default scope |
|---|---|---|---|
| [Apple](https://developer.apple.com/documentation/signinwithapple) | `:apple` | `Assent.Strategy.Apple` | `email` |
| [Auth0](https://auth0.com/docs/get-started/auth0-overview/create-applications) | `:auth0` | `Assent.Strategy.Auth0` | `email profile` |
| [Azure AD](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app) | `:azure_ad` | `Assent.Strategy.AzureAD` | `email profile` |
| [Basecamp](https://github.com/basecamp/bc3-api/blob/master/sections/authentication.md) | `:basecamp` | `Assent.Strategy.Basecamp` | — |
| [Bitbucket](https://support.atlassian.com/bitbucket-cloud/docs/use-oauth-on-bitbucket-cloud/) | `:bitbucket` | `Assent.Strategy.Bitbucket` | `account email` |
| [DigitalOcean](https://docs.digitalocean.com/reference/api/oauth/) | `:digital_ocean` | `Assent.Strategy.DigitalOcean` | `read write` |
| [Discord](https://discord.com/developers/docs/topics/oauth2) | `:discord` | `Assent.Strategy.Discord` | `identify email` |
| [Facebook](https://developers.facebook.com/documentation/facebook-login) | `:facebook` | `Assent.Strategy.Facebook` | `email` |
| [GitHub](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app) | `:github` | `Assent.Strategy.Github` | `user:email` |
| [GitLab](https://docs.gitlab.com/ee/integration/oauth_provider.html) | `:gitlab` | `Assent.Strategy.Gitlab` | `email profile` |
| [Google](https://developers.google.com/identity/protocols/oauth2) | `:google` | `Assent.Strategy.Google` | `email profile` |
| [Hack Club](https://auth.hackclub.com/docs/oauth-guide) | `:hackclub` | `Assent.Strategy.OAuth2` | `email slack_id name` |
| [Instagram](https://developers.facebook.com/docs/instagram-basic-display-api/getting-started) | `:instagram` | `Assent.Strategy.Instagram` | `user_profile` |
| [LINE](https://developers.line.biz/en/docs/line-login/integrate-line-login/) | `:line` | `Assent.Strategy.LINE` | `email profile` |
| [LinkedIn](https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2) | `:linkedin` | `Assent.Strategy.Linkedin` | `profile email` |
| [Slack](https://api.slack.com/authentication/oauth-v2) | `:slack` | `Assent.Strategy.Slack` | `openid email profile` |
| [Spotify](https://developer.spotify.com/documentation/web-api/concepts/authorization) | `:spotify` | `Assent.Strategy.Spotify` | `user-read-email` |
| [Strava](https://developers.strava.com/docs/authentication/) | `:strava` | `Assent.Strategy.Strava` | `read_all,profile:read_all` |
| [Stripe](https://docs.stripe.com/stripe-apps/api-authentication/oauth) | `:stripe` | `Assent.Strategy.Stripe` | — |
| [Telegram](https://core.telegram.org/widgets/login) | `:telegram` | `Assent.Strategy.Telegram` | — |
| [Twitch](https://dev.twitch.tv/docs/authentication/) | `:twitch` | `Assent.Strategy.Twitch` | `user:read:email` |
| [Twitter (X)](https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code) | `:twitter` | `Assent.Strategy.Twitter` | — (OAuth 1.0) |
| [VK](https://docs.strapi.io/cms/configurations/users-and-permissions-providers/vk) | `:vk` | `Assent.Strategy.VK` | `email` |
| [Zitadel](https://zitadel.com/docs/examples/identity-proxy/oauth2-proxy) | `:zitadel` | `Assent.Strategy.Zitadel` | `email profile` |

A dash in the scope column means the provider's `base_config/0` sets no default
scope. Basecamp, Stripe, and Telegram rely on the provider's own defaults, and
Twitter uses OAuth 1.0, which has no scope parameter.

## Configuring a provider

Every provider is configured under `:amur, :providers` as a keyword list. The
key is the provider atom and the value is a keyword list of credentials:

```elixir
config :amur,
  providers: [
    github: [
      client_id: System.fetch_env!("GITHUB_CLIENT_ID"),
      client_secret: System.fetch_env!("GITHUB_CLIENT_SECRET")
    ],
    google: [
      client_id: System.fetch_env!("GOOGLE_CLIENT_ID"),
      client_secret: System.fetch_env!("GOOGLE_CLIENT_SECRET")
    ]
  ]
```

The credentials you supply are merged over the provider's `base_config/0`, so
you only need to set what differs. Any key accepted by the underlying Assent
strategy can be passed here.

### Overriding scopes

When the default scope isn't fit for your needs, pass `:scopes` to request
exactly what you need:

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

`:scopes` is special-cased: Amur pops it out of the credentials and writes it
into the strategy's `:authorization_params` as `scope`, so it works uniformly
across providers regardless of how each strategy expects scopes to be set.

### Provider-specific configuration

Some providers need more than a client ID and secret:

- **Telegram** requires `bot_token`, `origin`, and `return_to` at runtime. Its
  `base_config/0` is empty, so everything comes from your config.
- **Zitadel** uses `client_authentication_method: "none"` with PKCE
  (`code_verifier: true`), since it is a public client.
- **Apple** and **Azure AD** use `response_mode: "form_post"`, so the callback
  arrives as a `POST` body rather than query parameters. Amur's router handles
  this because `Amur.Controller.callback/2` receives the merged params.

## Normalized users

Every provider's `normalize_user/1` returns a map in Amur's common shape. Amur
adds the `:provider` key before invoking your `:on_success` callback:

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
providers do not all return the same information, and provider-specific fields
may also be present. The public `Amur.User.t()` type represents this map.

### What each provider returns

The table below lists the fields each built-in provider populates. All providers
return `:uid`; the rest vary.

| Provider | `uid` | `email` | `name` | `avatar` | Extra |
|---|---|---|---|---|---|
| Apple | `sub` | ✓ | `given_name family_name` | `nil` | |
| Auth0 | `sub` | ✓ | ✓ | ✓ | |
| Azure AD | `sub` | ✓ | ✓ | ✓ | |
| Basecamp | `sub` | ✓ | ✓ | — | |
| Bitbucket | `sub` | ✓ | ✓ | ✓ | |
| DigitalOcean | `sub` | ✓ | — | — | |
| Discord | `sub` | ✓ | `preferred_username` | ✓ | |
| Facebook | `sub` | ✓ | ✓ | ✓ | |
| GitHub | `sub` | ✓ | `preferred_username` | ✓ | |
| GitLab | `sub` | ✓ | ✓ | ✓ | |
| Google | `sub` | ✓ | ✓ | ✓ | |
| Hack Club | `identity.id` | `identity.primary_email` | `first_name last_name` | — | `slack_id` |
| Instagram | `sub` | — | `preferred_username` or `name` | — | |
| LINE | `sub` | ✓ | ✓ | ✓ | |
| LinkedIn | `sub` | ✓ | ✓ | ✓ | |
| Slack | `sub` | ✓ | ✓ | ✓ | |
| Spotify | `sub` | ✓ | `name` or `preferred_username` | ✓ | |
| Strava | `sub` | — | `preferred_username` or `given_name family_name` | ✓ | |
| Stripe | `sub` | ✓ | — | — | |
| Telegram | `sub` | — | `given_name family_name` or `preferred_username` | ✓ | |
| Twitch | `sub` | ✓ | `preferred_username` or `name` | ✓ | |
| Twitter | `sub` | ✓ | ✓ | ✓ | |
| VK | `sub` | ✓ | `given_name family_name` | ✓ | |
| Zitadel | `sub` | ✓ | ✓ | ✓ | |

A dash means the provider does not set that key at all. `nil` means the key is
present but always `nil` (Apple never returns an avatar).

Hack Club is the one provider that nests its data: it reads from the `identity`
object in the response and additionally exposes `slack_id`.

## Provider modules

Each built-in provider is a module under `Amur.Providers`. Every module
implements the `Amur.Provider` behaviour, so you can read `base_config/0` and
`normalize_user/1` on any of them to see exactly what it does.

## Custom providers

If your provider isn't built in, define your own module with the
`Amur.Provider` behaviour. See [Custom providers](custom_providers.html).
