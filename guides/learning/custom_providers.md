# Custom providers

If your provider isn't built in, define your own module using the
`Amur.Provider` behaviour.

## Defining a provider

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

The provider name (`:my_provider` above) is what appears in the URL
(`/auth/my_provider`) and in the normalized user's `:provider` field.

## The behaviour

`Amur.Provider` has three required callbacks and one optional one.

### `strategy/0`

Returns the Assent strategy module that implements the OAuth protocol. Use
`Assent.Strategy.OAuth2` for a standard OAuth 2.0 provider, or one of Assent's
other strategies (`Assent.Strategy.OIDC`, `Assent.Strategy.OAuth`, …) when the
provider needs something different.

### `base_config/0`

Returns the provider's default configuration as a keyword list. This is merged
with the credentials from your `config :amur` (your values win), and Amur adds
`:strategy` and `:redirect_uri` on top.

Typical keys for an OAuth 2.0 provider:

| Key | Description |
|---|---|
| `base_url` | Origin the endpoint paths are relative to. |
| `authorization_endpoint` / `authorize_url` | Where the user is sent to authorize. |
| `token_endpoint` / `token_url` | Where the code is exchanged for a token. |
| `user_endpoint` / `user_url` | Where the user profile is fetched. |
| `authorization_params` | Extra query parameters, including `scope`. |
| `client_authentication_method` | How the client authenticates at the token endpoint. |

The exact key names depend on the Assent strategy. Reading a built-in provider
module's `base_config/0` is the best reference — see
[Providers](providers.html).

### `normalize_user/1`

Receives the raw user map returned by the provider and returns Amur's common
shape:

```elixir
@impl true
def normalize_user(user) do
  %{
    uid: user["id"],
    email: user["email"],
    name: user["name"],
    avatar: user["picture"]
  }
end
```

Only `:uid` is expected; the other common fields are optional. Any additional
keys you return are passed through to your `:on_success` callback, so you can
expose provider-specific data:

```elixir
@impl true
def normalize_user(user) do
  %{
    uid: user["id"],
    email: user["email"],
    organization: user["org"]["name"]
  }
end
```

Amur adds the `:provider` key itself before invoking the callback, so you don't
need to set it.

### `logo/0` (optional)

A custom provider has no bundled icon, so its sign-in button renders without
one. Give it a logo by implementing `logo/0`, which accepts the same forms as
the page-level [`logo`](sign_in_page.html#logo) configuration:

```elixir
@impl true
def logo, do: {:file, "priv/static/images/my_provider.svg"}
```

```elixir
@impl true
def logo, do: {:path, "/images/my_provider.svg"}
```

```elixir
@impl true
def logo do
  {:svg, """
  <svg viewBox="0 0 24 24" fill="currentColor">
    <circle cx="12" cy="12" r="10" />
  </svg>
  """}
end
```

A bare string is resolved automatically, as with the page logo: it is read as a
local file when one exists at that path, and treated as a URL otherwise. Inline
SVG inherits the page's text colour, so it adapts to light and dark mode.

When `logo/0` is not implemented (or returns `:error`), the provider falls back
to its bundled icon if one exists, and otherwise renders no icon. `use
Amur.Provider` provides a default `logo/0` returning `:error`, so you only need
to define it when you want an icon.

The page logo shown above the heading also falls back to the first provider that
has an icon, so a custom provider's logo is used there too when it is the first
one.

## A worked example

A provider that speaks plain OAuth 2.0 with a custom user shape:

```elixir
defmodule MyApp.Auth.Acme do
  use Amur.Provider

  @impl true
  def strategy, do: Assent.Strategy.OAuth2

  @impl true
  def base_config do
    [
      base_url: "https://auth.acme.test",
      authorization_endpoint: "/authorize",
      token_endpoint: "/token",
      user_endpoint: "/api/me",
      authorization_params: [scope: "openid email profile"],
      client_authentication_method: "client_secret_post"
    ]
  end

  @impl true
  def normalize_user(user) do
    %{
      uid: user["user_id"],
      email: user["email_address"],
      name: user["display_name"],
      avatar: user["avatar_url"],
      plan: user["plan"]
    }
  end

  @impl true
  def logo, do: {:svg, ~s|<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/></svg>|}
end
```

```elixir
config :amur,
  providers: [
    acme: MyApp.Auth.Acme
  ]
```

The user then signs in at `/auth/acme`, and `:on_success` receives a user with
`provider: "acme"` and a `:plan` key.

## Testing a custom provider

`normalize_user/1` is a pure function, so it is easy to test directly:

```elixir
test "normalizes an Acme user" do
  raw = %{"user_id" => "1", "email_address" => "a@b.test", "plan" => "pro"}

  assert MyApp.Auth.Acme.normalize_user(raw) == %{
           uid: "1",
           email: "a@b.test",
           plan: "pro"
         }
end
```
