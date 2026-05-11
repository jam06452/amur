# Amur

Simple OAuth for Plug apps.

Amur gives you a small OAuth callback flow and provider normalization layer.
It is now Plug-based and does not require Phoenix.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `amur` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:amur, "~> 0.1.0"}
  ]
end
```

## Setup

1. Add the dependency and configure your provider credentials.

```elixir
config :amur,
  providers: [
    github: [
      client_id: System.fetch_env!("GITHUB_CLIENT_ID"),
      client_secret: System.fetch_env!("GITHUB_CLIENT_SECRET")
    ]
  ],
  on_success: &MyApp.Accounts.find_or_create/3,
  on_failure: &MyApp.Accounts.auth_failed/2
```

2. Mount the router in your application router.

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/", MyAppWeb, alias: false do
    pipe_through :browser

    forward "/auth", Amur.Router
  end
end
```

`forward "/auth", Amur.Router` mounts the auth endpoints under `/auth`:

- `GET /auth/:provider` starts the OAuth flow.
- `GET /auth/:provider/callback` handles the provider callback.
- `GET /auth/logout` clears Amur's stored session params.

If you want a different base path, change the path you forward to. In Phoenix,
keep the forward inside a pipeline that runs `fetch_session` and `fetch_flash`
if your success or failure callbacks use session or flash helpers. Also set
`alias: false` on the scope that forwards `Amur.Router`, otherwise Phoenix will
rewrite it as `YourAppWeb.Amur.Router`.

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/amur>.

